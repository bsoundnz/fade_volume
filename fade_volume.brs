' =============================================================================================================================
' fade_volume plugin.  Gradually changes volume of an audio output connector over time in response to UDP message.
' Written and tested with HD224, BOS 8.5.47
' v1.0 (20 Oct 2024)
'
' HOW TO USE:	Send UDP message on port 6000 "fade_volume!<targetVolume>!<durationMs>" (e.g. "fade_volume!50!5000" to fade to 50% over 5 seconds)
' REQUIREMENTS:	Presentation must have a Variable called "storedVolume"
' Can also utiilize an optional Variable called "audioDevice".  Defaults to "analog" if Variable "audioDevice" not found.
' The variable can take the following strings:
'		"hdmi"
'		"usb" (not tested on HD224)
'		"spdif"
'		"analog" 
'
' KNOWN ISSUE: plugin will also respond on UDP Receiver port set in Presentation Settings / Interactive / Networking
' =============================================================================================================================


Function fade_volume_Initialize(msgPort As Object, userVariables As Object, bsp as Object)
	print "+++ fade_volume_Initialize - plugin entry"

	' Create and return the plugin object
    fade_volume = newfade_volume(msgPort, userVariables, bsp)
	
	' Declare a global variable to hold the audio output instance
	m.audioOutput = invalid  ' Initialize as invalid

    return fade_volume
End Function


Function newfade_volume(msgPort As Object, userVariables As Object, bsp as Object)
	print "+++ newfade_volume - Initializing plugin object"

	s = {}
	s.msgPort = msgPort  ' Store userVariables in plugin object scope
	s.userVariables = userVariables
	s.bsp = bsp
	s.ProcessEvent = fade_volume_ProcessEvent  ' Attach event handler
	s.objectName = "fade_volume_object"

	' UDP setup
	s.udpReceiverPort = 6000
	s.udpReceiver = CreateObject("roDatagramReceiver", s.udpReceiverPort)
	s.udpReceiver.SetPort(msgPort)

	' Copy Variable defaults to current values
	InitUserVar(s,"audioDevice")
	InitUserVar(s,"storedVolume")
	
	return s
End Function


Function fade_volume_ProcessEvent(event As Object) as boolean
	retval = false
	if type(event) = "roDatagramEvent" then
		print "+++ Received UDP Message: " + lcase(event)
		msg$ = event
		if (left(msg$,11) = "fade_volume") then
		    retval = Parsefade_volumePluginMsg(msg$, m)
		end if
	' else if (type(event) = "roUrlEvent") then
	' else if type(event) = "roHttpEvent" then
	' else if type(event) = "roTimerEvent" then
	end if

	return retval
End Function


Function Parsefade_volumePluginMsg(origMsg as string, s as object) as boolean
	retval = false
		
	' convert message to all lower case for easier string matching later
	msg = lcase(origMsg)
	r = CreateObject("roRegex", "^fade_volume", "i")
	match=r.IsMatch(msg)

	if match then
		retval = true
		
		' split the string
		r2 = CreateObject("roRegex", "!", "i")
		fields=r2.split(msg)
		numFields = fields.count()
		if (numFields < 3) or (numFields > 3) then
			print "+++ Incorrect number of fields for fade_volume command: "; msg
			return retval
		else if (numFields = 3) then
			command=fields[0]			
			volume=fields[1]
			duration=fields[2]
		end if
	end if

	newFade(s, volume, duration)

	return retval
end Function


Sub newFade(s as Object, volStr as String, durStr as String)
    ' Convert parameter strings to integers
    targetVolume = val(volStr)
    durationMs = val(durStr)

	' get the current value (as integer) stored in uservariable 
	currentVolume = val(GetUserVar(s, "storedVolume"))  ' Pass plugin object reference to access Variables
	
	if targetVolume = currentVolume
		print "+++ targetVolume" + Str(targetVolume) + " equals (stored) currentVolume" + Str(currentVolume) + ". Nothing to do!"
		return
	endif
		
	' Determine how much to change the volume per step
	steps = 50  ' Number of steps for the fade
	volumeStep = (targetVolume - currentVolume) / steps
	stepDuration = durationMs / steps  ' Time per step
	
	InitializeAudioOutput(s)  ' Ensure the audio output is initialized.

	' Fade logic...
	for i = 0 to steps
		' Calculate new volume
		newVolume = currentVolume + (volumeStep * i)

		' Ensure volume stays within valid bounds (0 to 100)
		if newVolume > 100 then
			newVolume = 100
		else if newVolume < 0 then
			newVolume = 0
		end if

		' Set the new audio output volume
		SetOutputVolume(s,newVolume)

		' Wait for the next step
		Sleep(stepDuration)
	end for
	
	SetUserVar(s, "storedVolume", newVolume)
End Sub


Function SetOutputVolume(s As Object, volume As Integer)
    m.audioOutput.SetVolume(volume)
    ' print "+++ Output volume set to: "; volume
End Function


Function InitializeAudioOutput(s As Object)
    if m.audioOutput = invalid then
        audDev = GetUserVar(s, "audioDevice")
        if val(audDev) = -1 then
            print "+++ Failed to retrieve audioDevice Variable. Using 'analog' as fallback."
            audDev = "analog"
        end if

        m.audioOutput = CreateObject("roAudioOutput", audDev)
        
        if m.audioOutput = invalid then
            print "+++ Error: Failed to initialize audio output for: "; audDev
        else
            print "+++ Audio output initialized."
        end if
    end if
End Function


Function InitUserVar(s As Object, varName As String)
    if s.userVariables.DoesExist(varName) then
        varLookup = s.userVariables.Lookup(varName)
		defVal = varLookup.defaultvalue$
        if SetUserVar(s,varName,defVal) = 0 then
            print "+++ Variable '" + varName + "' initialized with default: "; defVal
        else
            print "+++ Variable '" + varName + "' initialize failed."; varLookup.GetCurrentValue()
        endif
    else
        print "+++ Variable '" + varName + "' not found for initialize."
    endif
End Function


Function GetUserVar(s As Object, varName As String) As Dynamic
    ' Check if the variable exists within the provided object
    if s.userVariables.DoesExist(varName) then
        varLookup = s.userVariables.Lookup(varName)
        if varLookup <> invalid then
			' print "+++ Variable '" + varName + "' default value: "; varLookup.defaultvalue$
            currentValue = varLookup.GetCurrentValue()
			print "+++ Variable '" + varName + "' current value: "; currentValue
            return currentValue  ' returning value as string, Success
        else
			print "+++ Variable '" + varName + "' is invalid."
        endif
    else
		print "+++ Variable '" + varName + "' does not exist."
    endif
    ' Return a default value if retrieval fails
    return -1
End Function


Function SetUserVar(s As Object, varName As String, newValue As Dynamic) As Integer
    ' Check if the variable exists within the provided object
    if s.userVariables.DoesExist(varName) then
	    varLookup = s.userVariables.Lookup(varName)
		if varLookup <> invalid then
			' Update the Variable with the new value
			varLookup.SetCurrentValue(newValue,true)
			print "+++ Variable '" + varName + "' set to: "; newValue
			return 0  ' Success
		else
			print "+++ Variable '" + varName + "' is invalid."
		endif
    else
        print "+++ Variable '" + varName + "' not found."
    end if
    ' Return a default value if retrieval fails
    return -1
End Function
