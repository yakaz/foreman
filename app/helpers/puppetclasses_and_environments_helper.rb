module PuppetclassesAndEnvironmentsHelper
  def class_update_text pcs, env
    if pcs.empty?
      "Empty environment"
    elsif pcs.has_key? "_destroy_"
    elsif pcs.delete "_destroy_"
      if pcs.empty?
        "Deleted environment"
      else
        "Deleted environment #{env} and " + pcs.keys.to_sentence
      end
    else
      pcs.keys.to_sentence
    end
  end

  def import_proxy_select hash
    proxies = Environment.find_import_proxies
    action_buttons(
      proxies.map do |proxy|
        display_link_if_authorized("Import from #{proxy.name}", hash.merge(:proxy => proxy))
      end.flatten
    )
  end
end
