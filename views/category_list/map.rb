lambda do |item|
  if item['type'] == 'category' then
    emit item['_id'], nil
  end
end