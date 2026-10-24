---Storage domain encryption for the session files.
---
---This module encrypts with AES-256-GCM through OpenSSL 3's libcrypto, called with LuaJIT's FFI.
---The key is stretched from the session's directory with PBKDF2, so a file only decrypts in its
---own directory. GCM's tag checks the stored bytes before any decrypted byte is used, so an edited
---or corrupted file fails as a whole instead of decrypting into something else.

local ffi = require('ffi')

local M = {}

---PBKDF2 rounds that stretch the directory into the key
M.rounds = 200000
M.salt_length = 16
M.key_length = 32
M.nonce_length = 12
M.tag_length = 16

local EVP_CTRL_GCM_GET_TAG = 0x10
local EVP_CTRL_GCM_SET_TAG = 0x11

-- each declaration on its own, so one another plugin made already doesn't stop the rest
for _, declaration in ipairs({
	"typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;",
	"typedef struct evp_cipher_st EVP_CIPHER;",
	"typedef struct evp_md_st EVP_MD;",
	"typedef struct engine_st ENGINE;",
	"EVP_CIPHER_CTX *EVP_CIPHER_CTX_new(void);",
	"void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX *ctx);",
	"const EVP_CIPHER *EVP_aes_256_gcm(void);",
	"const EVP_MD *EVP_sha256(void);",
	"int EVP_EncryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *type, ENGINE *impl, const unsigned char *key, const unsigned char *iv);",
	"int EVP_EncryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl, const unsigned char *in, int inl);",
	"int EVP_EncryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl);",
	"int EVP_DecryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *type, ENGINE *impl, const unsigned char *key, const unsigned char *iv);",
	"int EVP_DecryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl, const unsigned char *in, int inl);",
	"int EVP_DecryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl);",
	"int EVP_CIPHER_CTX_ctrl(EVP_CIPHER_CTX *ctx, int type, int arg, void *ptr);",
	"int PKCS5_PBKDF2_HMAC(const char *pass, int passlen, const unsigned char *salt, int saltlen, int iter, const EVP_MD *digest, int keylen, unsigned char *out);",
	"int RAND_bytes(unsigned char *buf, int num);",
}) do
	pcall(ffi.cdef, declaration)
end

local libcrypto

---Get libcrypto, loading it the first time it's needed.
---
---A missing library is an environment failure, so this throws. A save then fails as a whole,
---and the session manager's save with it.
---
---@return ffi.namespace* lib The loaded libcrypto
local function crypto()
	if libcrypto == nil then
		for _, name in ipairs({ "crypto", "libcrypto.so.3", "libcrypto.3.dylib" }) do
			local ok, lib = pcall(ffi.load, name)
			if ok then
				libcrypto = lib
				break
			end
		end
		if libcrypto == nil then
			error("cavediver: OpenSSL 3's libcrypto was not found; it encrypts the session files.")
		end
	end
	return libcrypto
end

---Get random bytes from libcrypto.
---
---Throws when libcrypto can't make them.
---
---@param n integer How many bytes
---@return string bytes The n random bytes
function M.random_bytes(n)
	local buf = ffi.new("unsigned char[?]", n)
	if crypto().RAND_bytes(buf, n) ~= 1 then
		error("cavediver: libcrypto couldn't make random bytes.")
	end
	return ffi.string(buf, n)
end

---Derive the key for a session's directory and a file's salt.
---
---Runs PBKDF2 with SHA-256 for `M.rounds` rounds. Throws when libcrypto can't derive it.
---
---@param directory string The session's directory
---@param salt string The file's salt
---@return string key The key, `M.key_length` bytes long
function M.derive_key(directory, salt)
	local key = ffi.new("unsigned char[?]", M.key_length)
	local ok = crypto().PKCS5_PBKDF2_HMAC(directory, #directory, salt, #salt, M.rounds, crypto().EVP_sha256(), M.key_length, key)
	if ok ~= 1 then
		error("cavediver: libcrypto couldn't derive the session key.")
	end
	return ffi.string(key, M.key_length)
end

---Encrypt bytes with a fresh nonce.
---
---The `aad` is authenticated but not encrypted, so `M.open()` needs the same one. Throws when
---libcrypto can't encrypt.
---
---@param key string The key from `M.derive_key()`
---@param plaintext string The bytes to encrypt
---@param aad string Additional data to authenticate
---@return string sealed The nonce, the ciphertext and the tag, in that order
function M.seal(key, plaintext, aad)
	local lib = crypto()
	local nonce = M.random_bytes(M.nonce_length)
	local ctx = lib.EVP_CIPHER_CTX_new()
	local out = ffi.new("unsigned char[?]", #plaintext + 16)
	local tag = ffi.new("unsigned char[?]", M.tag_length)
	local outl = ffi.new("int[1]")
	local ok, sealed = pcall(function()
		assert(lib.EVP_EncryptInit_ex(ctx, lib.EVP_aes_256_gcm(), nil, key, nonce) == 1)
		assert(lib.EVP_EncryptUpdate(ctx, nil, outl, aad, #aad) == 1)
		assert(lib.EVP_EncryptUpdate(ctx, out, outl, plaintext, #plaintext) == 1)
		local length = outl[0]
		assert(lib.EVP_EncryptFinal_ex(ctx, out + length, outl) == 1)
		length = length + outl[0]
		assert(lib.EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, M.tag_length, tag) == 1)
		return nonce .. ffi.string(out, length) .. ffi.string(tag, M.tag_length)
	end)
	lib.EVP_CIPHER_CTX_free(ctx)
	if not ok then
		error("cavediver: libcrypto couldn't encrypt the session file.")
	end
	return sealed
end

---Decrypt what `M.seal()` made.
---
---The tag is checked before anything is returned, so nothing comes back from bytes that were
---changed.
---
---@param key string The key from `M.derive_key()`
---@param sealed string The nonce, the ciphertext and the tag, as `M.seal()` returned them
---@param aad string Additional data, the same as the seal's
---@return string|nil plaintext The decrypted bytes, or nil when the bytes, the key or the aad don't match
function M.open(key, sealed, aad)
	if #sealed < M.nonce_length + M.tag_length then
		return nil
	end
	local lib = crypto()
	local nonce = sealed:sub(1, M.nonce_length)
	local ciphertext = sealed:sub(M.nonce_length + 1, #sealed - M.tag_length)
	local tag = sealed:sub(#sealed - M.tag_length + 1)
	local ctx = lib.EVP_CIPHER_CTX_new()
	local out = ffi.new("unsigned char[?]", #ciphertext + 16)
	local outl = ffi.new("int[1]")
	-- copied by its length: a string initializer would add a zero byte past the buffer's end
	local tagbuf = ffi.new("unsigned char[?]", M.tag_length)
	ffi.copy(tagbuf, tag, M.tag_length)
	local plaintext
	local ok = pcall(function()
		assert(lib.EVP_DecryptInit_ex(ctx, lib.EVP_aes_256_gcm(), nil, key, nonce) == 1)
		assert(lib.EVP_DecryptUpdate(ctx, nil, outl, aad, #aad) == 1)
		assert(lib.EVP_DecryptUpdate(ctx, out, outl, ciphertext, #ciphertext) == 1)
		local length = outl[0]
		assert(lib.EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, M.tag_length, tagbuf) == 1)
		-- the tag is checked here; the bytes decrypted so far are thrown away when it fails
		assert(lib.EVP_DecryptFinal_ex(ctx, out + length, outl) == 1)
		plaintext = ffi.string(out, length + outl[0])
	end)
	lib.EVP_CIPHER_CTX_free(ctx)
	if not ok then
		return nil
	end
	return plaintext
end

return M
