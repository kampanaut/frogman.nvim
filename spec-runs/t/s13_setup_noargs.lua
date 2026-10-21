local ok, err = pcall(function() package.loaded['cavediver'] = nil; require('cavediver').setup() end)
P("setup() no args", ok and "ok" or tostring(err):gsub(os.getenv("CDV_PLUGIN"), "<plugin>"))
DONE()
