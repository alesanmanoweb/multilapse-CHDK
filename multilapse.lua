require 'signal'
signal.signal("SIGHUP", function() print('SIGHUP received\n') restart=true end)
signal.signal("SIGTERM", function() print('SIGTERM received\n') restart=true terminate=true end)

function cli_cmd(cmd)
	return cli:print_status(cli:execute(cmd))
end

function camera_init()
	print('Unpressing power button')
	cli_cmd('=post_levent_to_ui"UnpressPowerButton"')
	print('Going into rec mode')
	cli_cmd('rec')
	print('Setting P mode')
	cli_cmd('=require("capmode").set("P")')
	if(config_option.flash ~= nil) then
		print('Disabling flash: '..config_option.flash)
		cli_cmd('=set_prop(require"propcase".FLASH_MODE, '..config_option.flash..')')
	end
	if(config_option.whitebalance ~= nil) then
		print('Setting white balance: '..config_option.whitebalance)
		cli_cmd('=set_prop(require"propcase".WB_MODE, '..config_option.whitebalance..')') -- 0=Auto 1=daylight 2=cloudy 3=tungsten 4=Fluorescent 5=Fluorescent H 6=Flash 7=Custom
	end
	if(config_option.zoom ~= nil) then
		print('Setting zoom: '..config_option.zoom)
		cli_cmd('=set_zoom('..config_option.zoom..')')
	end
	if(config_option.resolution ~= nil) then
		print('Setting resolution: '..config_option.resolution)
		cli_cmd('=set_prop(require("propcase").RESOLUTION, '..config_option.resolution..')')
	end
	print('Disabling display')
	cli_cmd('=set_lcd_display(0)')
	--print('Locking autofocus')
	--cli_cmd('=set_aflock(1)')
end

function print_histo(histo, tot)
	bin = {}
	local bin_idx = 0
	for i = 0, 255, 16
	do
		local bin_count = 0
		for j = 0, 15
		do
			bin_count = bin_count + histo[i + j]
		end
		bin[bin_idx] = 100 * bin_count / tot
		bin_idx = bin_idx + 1
	end
	--[[
	for i = 0, 15
	do
		printf('%3d: %d\n', i, bin[i])
	end
	]]
	for i = 0, 15
	do
		printf('%3d: %s\n', i, string.rep('*', bin[i]))
	end
	--[[
	print('    ================================')
	for i = 8, 1, -1
	do
		printf('%d: |', i)
		for j = 0, 15
		do
			if bin[j] >= i * 10 - 5
			then
				printf('*')
			else
				printf(' ')
			end
			--printf('%3d: %s\n', i, string.rep('*', bin[i]))
		end
		printf('|\n')
	end
	print('    ================================')
	]]
end

function do_shoot(tv, sv, nd, imagename)
	--local cmd=string.format('remoteshoot -u=96 -tv=%d -sv=%d -nd=%s -sd=100000 image%d', tv, sv, nd, shot)
	local cmd=string.format('remoteshoot -u=96 -tv=%d -sv=%d -nd=%s -sd=100000 %s', tv, sv, nd, imagename)
	printf('%s\n',cmd)
	cli:execute(cmd)
	--  status, err = cli_cmd(cmd)
end

function capture_picture()
	if not config_night.enabled then
		timestamp = os.time()
		print('Remote shoot!')
		status, err = cli_cmd('remoteshoot -sd=100000 image')
	else
		hdrlo = false
		hdrhi = false
		print('Checking brightness level')
		-- try to get BV waiting max one second for three times
		status, values = con:execwait_pcall[[
			p = require('propcase')
			try_focus = 0
			max_try_focus = 3
			max_i = 300
			repeat
				i = 0
				press'shoot_half'
				repeat
					sleep(10)
					i = i + 1
					if get_shooting() then
						histo, histo_tot = get_live_histo()
						return
						{
							bv = get_prop(p.BV),
							tv = get_prop(p.TV),
							av = get_prop(p.AV),
							min_av = get_prop(p.MIN_AV),
							sv = get_prop(p.SV),
							histo = histo,
							histo_tot = histo_tot,
							try_focus  =try_focus,
							i = i
						}
					end
				until i > max_i
				release'shoot_half'
				sleep(1000)
				try_focus = try_focus + 1
			until try_focus > max_try_focus
			error('Focus failed!')
		]]
		if not status
		then
			print('*** *** *** Pre-shooting error: '..tostring(values))
			return false
		end
		timestamp = os.time()
		if values.bv >= config_night.threshold
		then
			-- HDR detection
			x = 0
			for i = 223, 255 do x = x + values.histo[i] end
			frac = x / values.histo_tot
			hdrhi = (frac > 0.10)
			for i = 0, 31 do x = x + values.histo[i] end
			frac = x / values.histo_tot
			hdrlo = (frac > 0.10)
			print('BV = '..values.bv..' TV = '..values.tv..' AV = '..values.av..' MIN_AV = '..values.min_av..' SV = '..values.sv..' HDRhi = '..tostring(hdrhi)..' HDRlo = '..tostring(hdrlo)..' try_focus = '..values.try_focus..' i = '..values.i)
			print_histo(values.histo, values.histo_tot)
			print('Remote shoot!')
			-- exposure calculation
			local nd = 'out'
			if values.min_av ~= values.av
			then
				nd = 'in'
			end
			do_shoot(values.tv, values.sv, nd, 'image')
			if hdrhi
			then
				do_shoot(values.tv + 96 * 2, values.sv, nd, 'imagehi')
			end
			if hdrlo
			then
				do_shoot(values.tv - 96 * 2, values.sv, nd, 'imagelo')
			end
			--status, err = cli_cmd('remoteshoot -sd=100000 image')
		else
			print('Night shoot!')
			status, err = cli_cmd('remoteshoot -sd=100000 -tv=16 image')
--		print('Base shot...')
--		status, err = cli_cmd('remoteshoot -sd=100000 -tv=16 base')
--		print('HDR shot 01...')
--		status, err = cli_cmd('remoteshoot -sd=100000 -tv=4 HDR01')
--		print('HDR shot 02...')
--		status, err = cli_cmd('remoteshoot -sd=100000 -tv=1 HDR02')
--		print('HDR shot 03...')
--		status, err = cli_cmd('remoteshoot -sd=100000 -tv=1/64 HDR03')
--		print('Enfuse...')
--		os.execute('enfuse --exposure-sigma=1 --output=fused.jpg HDR01.jpg HDR02.jpg HDR03.jpg')
--		print('Composite...')
--		os.execute('composite fused.jpg base.jpg /root/mask.png image.jpg')
--		print('Clean up...')
--		os.execute('rm base.jpg HDR01.jpg HDR02.jpg HDR03.jpg fused.jpg')
		-- stampare iso, iso noise reduction mode etc
		end
	end
	print(err)
	if not status
	then
		print('*** *** *** Shooting error')
		return false
	end
	--print('Disabling display')
	--cli_cmd('=set_backlight(0)')
	return true
end

function store_picture(timestamp)
	if(config_storage.resize) then
		-- we assume imagemagick is installed
		print('Resizing image...')
		os.execute('identify image.jpg')
		os.execute('mogrify -resize '..config_storage.resize_geometry..' image.jpg')
	end
	filename = string.format(config_base.camera_ID..'-%08x.jpg', timestamp)
	print('filename: '..filename)
	os.execute('mv image.jpg '..filename)
	if(config_storage.upload) then
		-- we assume curl is installed
		print('Uploading image...')
		if(config_storage.upload_type == 'http') then
			os.execute('curl -s -S -i -u "'..config_storage.upload_user..'" -F uploadedfile=@'..filename..' -F camera='..config_base.camera_ID..' -F timeStamp='..timestamp..' "'..config_storage.upload_URL..'"')
		elseif(config_storage.upload_type == 'ftp') then
			os.execute('curl -s -S -u "'..config_storage.upload_user..'" -T "'..filename..'" "'..config_storage.upload_URL..'"')
		end
	end
	if(config_storage.local_archive) then
		-- the following might fail if the path in the config is not correct
		os.execute('mv '..filename..' '..config_storage.archive_path)
	end
	if hdrhi
	then
		os.execute('mogrify -resize '..config_storage.resize_geometry..' imagehi.jpg')
		filename = string.format(config_base.camera_ID..'-%08x-hi.jpg', timestamp)
		os.execute('mv imagehi.jpg '..config_storage.archive_path..'/'..filename)
	end
	if hdrlo
	then
		os.execute('mogrify -resize '..config_storage.resize_geometry..' imagelo.jpg')
		filename = string.format(config_base.camera_ID..'-%08x-lo.jpg', timestamp)
		os.execute('mv imagelo.jpg '..config_storage.archive_path..'/'..filename)
	end
	if hdrhi or hdrlo
	then
		filename = string.format(config_base.camera_ID..'-%08x', timestamp)
		cmdline = 'enfuse '..filename..'* -o '..config_storage.archive_path..'/'..filename..'xxx.jpg'
		print(cmdline)
		os.execute(cmdline)
	end
end

config_mod = 0
terminate = false
while not terminate do -- main loop
	restart = false
	config_mod_check = lfs.attributes('/root/multilapse-CHDK/multilapse-config.lua', 'modification')
	if config_mod ~= config_mod_check
	then
		print('Reloading config file!')
		config_mod = config_mod_check
		dofile('/root/multilapse-CHDK/multilapse-config.lua')
	end
	print('Making sure camera is OFF')
	os.execute('/root/turnoff')
	print('Waiting 5s...')
	sys.sleep(5 * 1000)
	print('Turning camera ON')
	os.execute('/root/turnon')
	print('Waiting 5s for boot...')
	sys.sleep(5 * 1000)
	print('Connecting')
	cli_cmd('connect')
	camera_init()
	while not restart do -- shooting loop
		os.execute('echo 0 >/sys/class/leds/led1/brightness')
		status, ts, to = con:execwait_pcall[[return get_temperature(1), get_temperature(0)]]
		if not status
		then
			print('Error reading temperatures!')
			break
		end
		print('Temperature: sensor = '..ts..' optics = '..to)
		-- the following two lines allow to print sensor and lens temperatures in a CSV format, easy to grep
		time = os.date("*t")
		print(("SSTT,%02d%02d%02d-%02d%02d%02d,%02d,%02d"):format(time.year, time.month, time.day, time.hour, time.min, time.sec, ts, to))

		status = capture_picture()
		if not status
		then
			break
		end
		store_picture(timestamp)
		
		sleeptime = config_base.interval - os.time() % config_base.interval
		print('Sleeping '..sleeptime..'s')
		sys.sleep(1000 * sleeptime)
	end
	print('Turning camera OFF')
	cli_cmd([[. sleep(1000) post_levent_to_ui('PressPowerButton')]])
	cli_cmd('dis')
	print('Waiting 5s...')
	sys.sleep(1000 * 5)
	os.execute('/root/turnoff')
	sys.sleep(1000)
end
print('Exiting!\n\n')

