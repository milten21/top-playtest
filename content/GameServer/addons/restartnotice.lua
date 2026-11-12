RESTART_NOTICE_FILE = '/tmp/restart-notice'

HOOKmap_run_garner = HOOKmap_run_garner or map_run_garner
map_run_garner = function(map)
	local file = io.open(RESTART_NOTICE_FILE, 'r')
	if file then
		local text = file:read('*a')
		file:close()
		os.remove(RESTART_NOTICE_FILE)
		if text ~= '' then
			ScrollNotice(text, 2, 0xFFFFFF00)
			Notice(text)
		end
	end
	HOOKmap_run_garner(map)
end
