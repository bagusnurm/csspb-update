//ubah nama file ini jadi classmenu_ct.res replace ke folder /resource/ui/
"Resource/UI/ClassMenu_CT.res"
{
	"class_ct"
	{
		"ControlName"		"Frame"
		"fieldName"		"class_ct"
		"xpos"			"0"
		"ypos"			"0"
		"wide"			"640"
		"tall"			"480"
		"autoResize"		"0"
		"pinCorner"		"0"
		"visible"		"1"
		"enabled"		"1"
		"tabPosition"		"0"
	}
	"BaseBackground"
	{
		"ControlName" "ImagePanel"
		"fieldName" "BaseBackground"
		"xpos" "107" //"xpos" "c-320" = 16:9, "xpos" "c-220" = 4:3
		"ypos" "20"
		"zpos" "-10"
		"wide" "430"
		"tall" "450"
		"visible" "1"
		"enabled" "1"
		"scaleImage" "1"
		"autoResize" "0"
		"pinCorner" "0"
		"image" "buymenu/base"
	}
	"SysMenu"
	{
		"ControlName"		"Menu"
		"fieldName"		"SysMenu"
		"xpos"			"0"
		"ypos"			"0"
		"wide"			"64"
		"tall"			"24"
		"autoResize"		"0"
		"pinCorner"		"0"
		"visible"		"0"
		"enabled"		"0"
		"tabPosition"		"0"
	}

	"reminder"
	{
		"ControlName"		"Label"
		"fieldName"		"reminder"
		"xpos"		"290"
		"ypos"		"22"
		"wide"		"450"
		"tall"		"48"
		"autoResize"		"0"
		"pinCorner"		"0"
		"visible"		"1"
		"enabled"		"1"
		"labelText"		"Reminder!"
		"textAlignment"		"west"
		"dulltext"		 "0"
		"brighttext"	"0"
		"font"		"MenuTitle"
	}

	"classInfoLabel"
	{
		"ControlName"		"Label"
		"fieldName"		"classInfoLabel"
		"xpos"			"210"
		"ypos"			"72"
		"wide"			"180"
		"tall"			"24"
		"autoResize"		"0"
		"pinCorner"		"0"
		"visible"		"0"
		"enabled"		"1"
		"labelText"		"#Cstrike_Class_Info"
		"textAlignment"		"west"
		"dulltext"		"0"
		"brighttext"		"1"
	}

	"ClassInfo"
	{
		"ControlName"		"Panel"
		"fieldName"		"ClassInfo"
		"xpos"			"210"
		"ypos"			"116"
		"wide"			"50"
		"tall"			"50"
		"autoResize"		"3"
		"pinCorner"		"0"
		"visible"		"0"
		"enabled"		"0"
		"tabPosition"		"0"
	}

	"title"
	{
		"ControlName"		"Label"
		"fieldName"		"title"
		"xpos"				"200"
		"ypos"				"90"
		"wide"			"250"
		"tall"			"40"
		"autoResize"		"0"
		"pinCorner"		"0"
		"visible"			"1"
		"enabled"			"1"
		"labelText"		"You are about to using..."		
		"textAlignment"		"center"
		"dulltext"			"1"
		"brighttext"		"0"
		"font"		         "MenuTitle"

	}

	"ct-name"
	{
		"ControlName"		"Label"
		"fieldName"		"ct-name"
		"xpos"				"200"
		"ypos"				"300"
		"wide"			"250"
		"tall"			"40"
		"autoResize"		"0"
		"pinCorner"		"0"
		"visible"			"1"
		"enabled"			"1"
		"labelText"		"Lisa"		
		"textAlignment"		"center"
		"dulltext"			"1"
		"brighttext"		"0"
           "font"		         "MenuTitle"

	}

	"lisa"
	{
		"ControlName"		"MouseOverPanelButton"
		"fieldName"		"lisa"
		"xpos"		"290"
		"ypos"		"430"
		"wide"		"60"
		"tall"		"30"
		"autoResize"		"0"
		"pinCorner"		"2"
		"visible"		     "1"
		"enabled"		     "1"
		"tabPosition"		"0"
		"labelText"		"OK"
		"textAlignment"		"center"
		"dulltext"		      "0"
		"brighttext"	     	"0"
		"sound_armed" "ui/UI_Button_Hover.wav"
		"sound_depressed" "ui/UI_Button_Equip.wav"
		"command"		      "sm_Lisa"
	}


	"OKImage"
	{
		"ControlName"	"ImagePanel"
		"xpos"		"290"
		"ypos"		"430"
		"wide"		"60"
		"tall"		"30"
		"zpos"		"-1"
		"visible"		"1"
		"enabled"		"1"
		"image"			"buymenu/baseButton"
		"scaleImage"	"1"	
	}	




}
