module SettingsHelper

  def value setting
    case setting.settings_type
    when "boolean"
      edit_select(setting, :value, {:select_values => {:true => "true", :false => "false"}.to_json } )
    when "enum"
      proposals = setting.enum_values
      proposals = proposals.keys if proposals.is_a? Hash
      proposals = Hash[proposals.map { |v| [v.to_sym, v.to_s] }]
      edit_select(setting, :raw_value, {:select_values => proposals.to_json} )
    else
      edit_textfield(setting, :value,{:helper => :show_value})
    end
  end

  def show_value setting
    case setting.settings_type
    when "array"
      "[ " + setting.raw_value.join(", ") + " ]"
    else
      setting.raw_value
    end
  rescue
    setting.raw_value
  end
end
