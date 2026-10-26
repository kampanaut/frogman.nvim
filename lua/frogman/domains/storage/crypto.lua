---Storage domain encryption for the session files.
---
---This module encrypts with AES-256-GCM through OpenSSL's libcrypto, 3 or 4, called with LuaJIT's FFI.
---The key is stretched from the session's directory with PBKDF2, so a file only decrypts in its
---own directory. GCM's tag checks the stored bytes before any decrypted byte is used, so an edited
---or corrupted file fails as a whole instead of decrypting into something else.

-- LuaJIT's FFI, taken the first time libcrypto is needed, so a Neovim without LuaJIT still loads
-- the plugin, and only what encrypts fails, saying so
local ffi

local M = {}

---PBKDF2 rounds that stretch the directory into the key
M.rounds = 200000
M.salt_length = 16
M.key_length = 32
M.nonce_length = 12
M.tag_length = 16

local EVP_CTRL_GCM_GET_TAG = 0x10
local EVP_CTRL_GCM_SET_TAG = 0x11

local libcrypto
-- the libcrypto_path values that didn't load, each said once
local warned = {}
-- the last search that loaded nothing: the libcrypto_path it was made with, and its error
local failed

---Get libcrypto, loading it the first time it's needed.
---
---The config's `libcrypto_path` is tried first, then OpenSSL 3's and OpenSSL 4's names. A path that
---won't load, or loads and isn't libcrypto, is said once, and the names after it are tried. A
---missing library is an environment failure, so this throws, naming each name tried, and throws
---the same again until `libcrypto_path` changes. A save then fails as a whole, and the session
---manager's save with it.
---
---@return ffi.namespace* lib The loaded libcrypto
local function crypto()
	if libcrypto == nil then
		local configured = require('frogman.configs').libcrypto_path
		if failed and failed.configured == configured then
			error(failed.error, 0) -- nothing new to try: the same search loaded nothing
		end
		if ffi == nil then
			local ok, module = pcall(require, 'ffi')
			if not ok then
				error("cavediver: this Neovim has no LuaJIT FFI, which encrypts the session files; a Neovim built with LuaJIT has it.", 0)
			end
			ffi = module
			-- each function under a name of cavediver's own, its symbol named by __asm__, so another
			-- plugin's declaration of the same function, even a different one, never stands in for it
			for _, declaration in ipairs({
				"typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;",
				"typedef struct evp_cipher_st EVP_CIPHER;",
				"typedef struct evp_md_st EVP_MD;",
				"typedef struct engine_st ENGINE;",
				'EVP_CIPHER_CTX *cdv_EVP_CIPHER_CTX_new(void) __asm__("EVP_CIPHER_CTX_new");',
				'void cdv_EVP_CIPHER_CTX_free(EVP_CIPHER_CTX *ctx) __asm__("EVP_CIPHER_CTX_free");',
				'const EVP_CIPHER *cdv_EVP_aes_256_gcm(void) __asm__("EVP_aes_256_gcm");',
				'const EVP_MD *cdv_EVP_sha256(void) __asm__("EVP_sha256");',
				'int cdv_EVP_EncryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *type, ENGINE *impl, const unsigned char *key, const unsigned char *iv) __asm__("EVP_EncryptInit_ex");',
				'int cdv_EVP_EncryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl, const unsigned char *in, int inl) __asm__("EVP_EncryptUpdate");',
				'int cdv_EVP_EncryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl) __asm__("EVP_EncryptFinal_ex");',
				'int cdv_EVP_DecryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *type, ENGINE *impl, const unsigned char *key, const unsigned char *iv) __asm__("EVP_DecryptInit_ex");',
				'int cdv_EVP_DecryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl, const unsigned char *in, int inl) __asm__("EVP_DecryptUpdate");',
				'int cdv_EVP_DecryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl) __asm__("EVP_DecryptFinal_ex");',
				'int cdv_EVP_CIPHER_CTX_ctrl(EVP_CIPHER_CTX *ctx, int type, int arg, void *ptr) __asm__("EVP_CIPHER_CTX_ctrl");',
				'int cdv_PKCS5_PBKDF2_HMAC(const char *pass, int passlen, const unsigned char *salt, int saltlen, int iter, const EVP_MD *digest, int keylen, unsigned char *out) __asm__("PKCS5_PBKDF2_HMAC");',
				'int cdv_RAND_bytes(unsigned char *buf, int num) __asm__("RAND_bytes");',
			}) do
				pcall(ffi.cdef, declaration)
			end
		end
		local names = {}
		if type(configured) == "string" and configured ~= "" then
			table.insert(names, vim.fs.normalize(configured)) -- ~ and $HOME expanded, as Neovim's own paths are
		end
		if ffi.os ~= "OSX" then
			-- the versioned names first, OpenSSL 3's before 4's
			vim.list_extend(names, { "libcrypto.so.3", "libcrypto.so.4", "crypto" })
		else
			-- full paths only: for a bare name dlopen also searches the current directory, which a project
			-- could fill, and the bare libcrypto there is the system's own, which stops any program that
			-- isn't Apple's. Homebrew's openssl@3 and openssl@4, linked or not, and MacPorts'.
			vim.list_extend(names, {
				"/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib", "/usr/local/opt/openssl@3/lib/libcrypto.3.dylib",
				"/opt/homebrew/lib/libcrypto.3.dylib", "/usr/local/lib/libcrypto.3.dylib", "/opt/local/lib/libcrypto.3.dylib",
				"/opt/homebrew/opt/openssl@4/lib/libcrypto.4.dylib", "/usr/local/opt/openssl@4/lib/libcrypto.4.dylib",
				"/opt/homebrew/lib/libcrypto.4.dylib", "/usr/local/lib/libcrypto.4.dylib",
			})
		end
		for i, name in ipairs(names) do
			local ok, lib = pcall(ffi.load, name)
			-- a library that loads but has no libcrypto in it counts as one that won't load
			local why = not ok and tostring(lib):match("[^\n]*")
				or not pcall(function() return lib.cdv_EVP_aes_256_gcm end) and "it isn't libcrypto (no EVP_aes_256_gcm)"
			if not why then
				libcrypto = lib
				break
			elseif i == 1 and type(configured) == "string" and configured ~= "" and not warned[name] then
				warned[name] = true
				vim.notify("cavediver: libcrypto_path (" .. name .. ") didn't load: " .. why
					.. "; trying cavediver's own list.", vim.log.levels.WARN)
			end
		end
		if libcrypto == nil then
			failed = { configured = configured, error = "cavediver: OpenSSL's libcrypto was not found; it encrypts the session files. Tried: "
				.. table.concat(names, ", ") .. ". Set libcrypto_path to its file." }
			error(failed.error, 0)
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
	local lib = crypto()
	local buf = ffi.new("unsigned char[?]", n)
	if lib.cdv_RAND_bytes(buf, n) ~= 1 then
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
	local lib = crypto()
	local key = ffi.new("unsigned char[?]", M.key_length)
	local ok = lib.cdv_PKCS5_PBKDF2_HMAC(directory, #directory, salt, #salt, M.rounds, lib.cdv_EVP_sha256(), M.key_length, key)
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
	local ctx = lib.cdv_EVP_CIPHER_CTX_new()
	if ctx == nil then
		error("cavediver: libcrypto couldn't make a cipher context (out of memory?).", 0) -- an environment failure
	end
	local out = ffi.new("unsigned char[?]", #plaintext + 16)
	local tag = ffi.new("unsigned char[?]", M.tag_length)
	local outl = ffi.new("int[1]")
	local ok, sealed = pcall(function()
		assert(lib.cdv_EVP_EncryptInit_ex(ctx, lib.cdv_EVP_aes_256_gcm(), nil, key, nonce) == 1)
		assert(lib.cdv_EVP_EncryptUpdate(ctx, nil, outl, aad, #aad) == 1)
		assert(lib.cdv_EVP_EncryptUpdate(ctx, out, outl, plaintext, #plaintext) == 1)
		local length = outl[0]
		assert(lib.cdv_EVP_EncryptFinal_ex(ctx, out + length, outl) == 1)
		length = length + outl[0]
		assert(lib.cdv_EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, M.tag_length, tag) == 1)
		return nonce .. ffi.string(out, length) .. ffi.string(tag, M.tag_length)
	end)
	lib.cdv_EVP_CIPHER_CTX_free(ctx)
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
	local ctx = lib.cdv_EVP_CIPHER_CTX_new()
	if ctx == nil then
		error("cavediver: libcrypto couldn't make a cipher context (out of memory?).", 0) -- an environment failure
	end
	local out = ffi.new("unsigned char[?]", #ciphertext + 16)
	local outl = ffi.new("int[1]")
	-- copied by its length: a string initializer would add a zero byte past the buffer's end
	local tagbuf = ffi.new("unsigned char[?]", M.tag_length)
	ffi.copy(tagbuf, tag, M.tag_length)
	local plaintext
	local ok = pcall(function()
		assert(lib.cdv_EVP_DecryptInit_ex(ctx, lib.cdv_EVP_aes_256_gcm(), nil, key, nonce) == 1)
		assert(lib.cdv_EVP_DecryptUpdate(ctx, nil, outl, aad, #aad) == 1)
		assert(lib.cdv_EVP_DecryptUpdate(ctx, out, outl, ciphertext, #ciphertext) == 1)
		local length = outl[0]
		assert(lib.cdv_EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, M.tag_length, tagbuf) == 1)
		-- the tag is checked here; the bytes decrypted so far are thrown away when it fails
		assert(lib.cdv_EVP_DecryptFinal_ex(ctx, out + length, outl) == 1)
		plaintext = ffi.string(out, length + outl[0])
	end)
	lib.cdv_EVP_CIPHER_CTX_free(ctx)
	if not ok then
		return nil
	end
	return plaintext
end

return M
