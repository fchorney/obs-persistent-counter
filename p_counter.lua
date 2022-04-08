obs           = obslua
source_name   = ""

file_path     = ""
active        = false
hk_descriptor = ""

hotkey_inc_id = obs.OBS_INVALID_HOTKEY_ID
hotkey_dec_id = obs.OBS_INVALID_HOTKEY_ID

----------------------------------------------------

-- When a source is activated, check to see if it is `source_name` and if so, save the status of the source
function activate_signal(cd, activating)
    local source = obs.calldata_source(cd, "source")
    if source ~= nil then
        local name = obs.obs_source_get_name(source)
        if (name == source_name) then
            active = activating
        end
    end
end

-- Triggers when any source is activated
function source_activated(cd)
    activate_signal(cd, true)
end

-- Triggers when any source is deactivated
function source_deactivated(cd)
    activate_signal(cd, false)
end

-- Clamp a value so that it can not go below 0
function pos_clamp(value)
    if value < 0 then
        value = 0
    end
    return value
end

-- Check if a file exists
function file_exists(file)
    local f = io.open(file, "rb")
    if f then f:close() end
    return f ~= nil
end

-- Get the current counter in the file, apply the change, and save the new value
-- path: Path to file
-- change: either positive 1 or negative 1
function update_file_counter(path, change)
    local value = 0

    -- If the file exists, read the value
    if file_exists(path) then
        local f = io.open(path, "rb")
        value = tonumber(f:read("*all"))
        f:close()
    end

    -- Apply the change
    value = pos_clamp(value + change)

    -- Save the new value to the file
    local f = io.open(path, "w")
    f:write(tostring(value))
    f:close()

    return value
end

-- Increment the file counter
function press_inc(pressed)
    if not pressed or not active then
        return
    end

    update_file_counter(file_path, 1)
end

-- Decrement the file counter
function press_dec(pressed)
    if not pressed or not active then
        return
    end

    update_file_counter(file_path, -1)
end

-- Triggers when the increment button is clicked
function inc_button_clicked(props, p)
    press_inc(true)
    return false
end

-- Triggers when the decrement button is clicked
function dec_button_clicked(props, p)
    press_dec(true)
    return false
end

----------------------------------------------------

-- Define the properties for the script that the user can change
function script_properties()
    local props = obs.obs_properties_create()

    -- Add a descriptor the user can use for identifying hotkeys
    obs.obs_properties_add_text(props, "hk_desc", "HotKey Descriptor", obs.OBS_TEXT_DEFAULT)

    -- List any text sources, the user will want to choose the text source displaying the file contents
    local p = obs.obs_properties_add_list(props, "source", "Text Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            source_id = obs.obs_source_get_unversioned_id(source)
            if source_id == "text_gdiplus" or source_id == "text_ft2_source" or source_id == "text_gdiplus_v2" or source_id == "text_ft2_source_v2" then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(p, name, name)
            end
        end
    end
    obs.source_list_release(sources)

    -- File path to the file that stores the count
    obs.obs_properties_add_path(props, "path_file", "File Path", obs.OBS_PATH_FILE_SAVE, "Text File (*.txt)", NULL)

    -- Increment and Decrement buttons that can be mapped to hotkeys
    obs.obs_properties_add_button(props, "inc_button", "Increment Value", inc_button_clicked)
    obs.obs_properties_add_button(props, "dec_button", "Decrement Value", dec_button_clicked)

    return props
end

-- Displays the given description on the scripts screen
function script_description()
    return "Increments or Decrements a counter from a file. When 'Text Source' is not active, the hotkeys will be deactivated"
end

-- This is triggered whenever the settings for this script change
function script_update(settings)
    file_path = obs.obs_data_get_string(settings, "path_file")
    source_name = obs.obs_data_get_string(settings, "source")
    hk_descriptor = obs.obs_data_get_string(settings, "hk_desc")

    -- If the file doesn't yet exist, create it
    if file_path ~= "" then
        update_file_counter(file_path, 0)
    end
end

-- This is triggered whenever the script is saved
-- This is used to store the hotkey combos
function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(inc_hotkey)
    obs.obs_data_set_array(settings, "inc_hotkey", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    local hotkey_save_array = obs.obs_hotkey_save(dec_hotkey)
    obs.obs_data_set_array(settings, "dec_hotkey", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

-- This is triggered on script startup
function script_load(settings)
    -- Connect activation/deactivation signal callbacks
    local sh = obs.obs_get_signal_handler()
    obs.signal_handler_connect(sh, "source_activate", source_activated)
    obs.signal_handler_connect(sh, "source_deactivate", source_deactivated)

    hk_descriptor = obs.obs_data_get_string(settings, "hk_desc")
    if hk_descriptor == "" then
        hk_descriptor = "Default"
    end

    -- Load the saved hotkeys for the increment/decrement buttons
    inc_hotkey = obs.obs_hotkey_register_frontend("increment_count", "Increment " .. hk_descriptor .. " Counter", press_inc)
    local hotkey_save_array = obs.obs_data_get_array(settings, "inc_hotkey")
    obs.obs_hotkey_load(inc_hotkey, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    dec_hotkey = obs.obs_hotkey_register_frontend("decrement_count", "Decrement " .. hk_descriptor .. " Counter", press_dec)
    local hotkey_save_array = obs.obs_data_get_array(settings, "dec_hotkey")
    obs.obs_hotkey_load(dec_hotkey, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    -- Grab the source name if it is currently set so we know if this script should be active or not
    source_name = obs.obs_data_get_string(settings, "source")
    if source_name ~= "" then
        local source = obs.obs_get_source_by_name(source_name)
        if source ~= nil and obs.obs_source_active(source) then
            active = true
        else
            active = false
        end
    else
        active = false
    end
end
