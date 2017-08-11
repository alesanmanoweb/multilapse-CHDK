config_mod = 0
exit_program = false
while true do -- main loop
	config_mod_check = lfs.attributes('/root/multilapse-CHDK/multilapse-config.lua', 'modification')
	if config_mod ~= config_mod_check
	then
		print('Reloading config file!')
		config_mod = config_mod_check
		dofile('/root/multilapse-CHDK/multilapse-config.lua')
	end
	reinit = false -- used to 'manually break the shooting loop
	print('Making sure camera is OFF')
	os.execute('/root/turnoff')
	print('Waiting 5s...')
	sys.sleep(5 * 1000)
	print('Turning camera ON')
	os.execute('/root/turnon')
	print('Waiting 5s for boot...')
	sys.sleep(5 * 1000)
	print('Connecting')
	cli:execute('connect')
	print('Going into rec mode')
	cli:execute('rec')
	print('Setting P mode')
	cli:execute('=require("capmode").set("P")')
	print('Disabling flash')
	cli:execute('=set_prop(require"propcase".FLASH_MODE,2)')
	print('White balance')
	cli:execute('=set_prop(require"propcase".WHITE_BALANCE,4)')
	print('Disabling display')
	cli:execute('=set_lcd_display(0)')
	print('Setting zoom')
	cli:execute('=set_zoom(0)')
	print('Setting resolution')
	--cli:execute('=set_prop(require("propcase").WB_MODE, 1)') -- 0=Auto 1=daylight 2=cloudy
	cli:execute('=set_prop(require("propcase").RESOLUTION, 1)')
	--print('Locking autofocus')
	--cli:execute('=set_aflock(1)')
	while true do -- shooting loop
		os.execute('echo 0 >/sys/class/leds/led1/brightness')
		status, ts = con:execwait_pcall[[return get_temperature(1)]]
		if not status
		then
			print('Error reading temperature(1)')
			break
		end
		status, to = con:execwait_pcall[[return get_temperature(0)]]
		if not status
		then
			print('Error reading temperature(0)')
			break
		end
		print('Temperature: sensor = '..ts..' optics = '..to) --crashed here because result is not a table
		-- the following two lines allow to print sensor and lens temperatures in a CSV format, easy to grep
		time = os.date("*t")
		print(("SSTT,%02d%02d%02d-%02d%02d%02d,%02d,%02d"):format(time.year, time.month, time.day, time.hour, time.min, time.sec, ts, to))

		print('Checking brightness level')
		-- try to get BV waiting max one second for three times
		status, bv = con:execwait_pcall[[
			press'shoot_half'
			try_focus = 0
			max_try_focus = 3
			i = 0
			max_i = 300
			repeat
				repeat
					sleep(10)
					i = i + 1
					if get_shooting() then
						return get_prop(require('propcase').BV)
					end
				until i > max_i
				if i > max_i then
					release'shoot_half'
					sleep(1000)
				end
				try_focus = try_focus + 1
			until try_focus > max_try_focus
			error('Focus failed!')
		]]
		if not status
		then
			print('*** *** *** Pre-shooting error')
			break
			bv = 0
		else
			print('BV = '..bv)
		end
		timestamp = os.time()
		if bv >= config.threshold
		then
			print('Remote shoot!')
			status, err = cli:execute('remoteshoot -sd=100000 image')
		else
			print('Night shoot!')
			status, err = cli:execute('remoteshoot -sd=100000 -tv=16 image')
--			print('Base shot...')
--			status, err = cli:execute('remoteshoot -sd=100000 -tv=16 base')
--			print('HDR shot 01...')
--			status, err = cli:execute('remoteshoot -sd=100000 -tv=4 HDR01')
--			print('HDR shot 02...')
--			status, err = cli:execute('remoteshoot -sd=100000 -tv=1 HDR02')
--			print('HDR shot 03...')
--			status, err = cli:execute('remoteshoot -sd=100000 -tv=1/64 HDR03')
--			print('Enfuse...')
--			os.execute('enfuse --exposure-sigma=1 --output=fused.jpg HDR01.jpg HDR02.jpg HDR03.jpg')
--			print('Composite...')
--			os.execute('composite fused.jpg base.jpg /root/mask.png image.jpg')
--			print('Clean up...')
--			os.execute('rm base.jpg HDR01.jpg HDR02.jpg HDR03.jpg fused.jpg')
			-- stampare iso, iso noise reduction mode etc
		end
		print(err)
		if not status
		then
			print('*** *** *** Shooting error')
			break
		end
		--print('Disabling display')
		--cli:execute('=set_backlight(0)')
		print('Resizing image...')
		os.execute('identify image.jpg')
		os.execute('mogrify -resize 2048x1536 image.jpg')
		filename = string.format(config.camera_ID..'-%08x.jpg', timestamp)
		os.execute('mv image.jpg '..filename)
		print('Uploading image...')
		os.execute('curl -s -S -i -u "'..config.user..'" -F uploadedfile=@'..filename..' -F camera='..config.camera_ID..' -F timeStamp='..timestamp..' '..config.upload_URL)
		os.execute('mv '..filename..' /root/archive/')
		while true do -- sleeping loop
			sleeptime = config.interval - os.time() % config.interval
			--print('Sleeping '..sleeptime..'s')
			if sleeptime > 10
			then
				--print('sleeptime>10; sleeping 10s')
				sys.sleep(1000 * 10)
				if lfs.attributes('/var/run/multilapse-exit')
				then
					print('exit file present')
					os.remove('/var/run/multilapse-exit')
					exit_program = true
					reinit = true
					break
				end
				if lfs.attributes('/var/run/multilapse-trigger')
				then
					print('trigger file present')
					os.remove('/var/run/multilapse-trigger')
					reinit = true
					break
				end
			else
				print('last sleep before planned shooting')
				sys.sleep(1000 * sleeptime)
				break
			end
		end
		if reinit then break end
	end
	print('Turning camera OFF')
	cli:execute([[. sleep(1000) post_levent_to_ui('PressPowerButton')]])
	cli:execute('dis')
	print('Waiting 5s...')
	sys.sleep(1000 * 5)
	os.execute('/root/turnoff')
	sys.sleep(1000)
	if exit_program then break end
end

