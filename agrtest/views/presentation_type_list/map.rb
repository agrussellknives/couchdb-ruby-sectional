lambda do |item|
  return unless item.has_key? 'presentations'
  item['presentations'].each_value do |p|
    emit(p['type'],nil)
  end
end