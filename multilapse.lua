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
	print('Disabling flash')
	cli_cmd('=set_prop(require"propcase".FLASH_MODE,2)')
	print('White balance')
	cli_cmd('=set_prop(require"propcase".WB_MODE,0)') -- 0=Auto 1=daylight 2=cloudy 3=tungsten 4=Fluorescent 5=Fluorescent H 6=Flash 7=Custom
	print('Disabling display')
	cli_cmd('=set_lcd_display(0)')
	print('Setting zoom')
	cli_cmd('=set_zoom('..config.zoom..')')
	print('Setting resolution')
	cli_cmd('=set_prop(require("propcase").RESOLUTION, 1)')
	--print('Locking autofocus')
	--cli_cmd('=set_aflock(1)')
end

function capture_picture()
	print('Checking brightness level')
	-- try to get BV waiting max one second for three times
	status, bv, try_focus, i = con:execwait_pcall[[
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
					return get_prop(require('propcase').BV), try_focus, i
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
		print('*** *** *** Pre-shooting error')
		return false
	else
		print('BV = '..bv..' try_focus = '..try_focus..' i = '..i)
	end
	timestamp = os.time()
	if bv >= config.threshold
	then
		print('Remote shoot!')
		status, err = cli_cmd('remoteshoot -sd=100000 image')
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

function store_picture()
	print('Resizing image...')
	os.execute('identify image.jpg')
	os.execute('mogrify -resize 2048x1536 image.jpg')
	filename = string.format(config.camera_ID..'-%08x.jpg', timestamp)
	os.execute('mv image.jpg '..filename)
	print('Uploading image...')
	os.execute('curl -s -S -i -u "'..config.user..'" -F uploadedfile=@'..filename..' -F camera='..config.camera_ID..' -F timeStamp='..timestamp..' '..config.upload_URL)
	os.execute('mv '..filename..' /root/archive/')
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
		store_picture()
		
		sleeptime = config.interval - os.time() % config.interval
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

