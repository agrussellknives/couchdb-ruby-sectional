lambda do |head,req|
  rows = []
  row = get_row
  collated_row = nil
  while row = get_row do
    if not collated_row then collated_row = {} end
      
    if collated_row then
      if collated_row['_id'] == row['key'][0..1] then        
        # add presentation master fields to base object
        if row['key'][2] == nil then
          collated_row = collated_row.merge(row['value'])
        end
        
        # add value of each row to collated structure
        row['value'].keys.each do |type|
          if not collated_row.keys.include? type then
            collated_row[type] = []
          end
          collated_row[type] << row['value'][type]
        end
      else # we have gotten a different key
        send collated_row.to_json
        collated_row = nil
        redo
      end
    end
  end
end 