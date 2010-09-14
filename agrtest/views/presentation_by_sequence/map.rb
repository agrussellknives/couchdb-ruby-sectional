lambda do |item|
  # update me!
  holder = {}
  keycodes = item['keycodes'] || {}
  master_item = item.clone
  
  master_item.delete('keycodes')
  master_item.delete('presentations')

  return unless item.has_key? 'presentations'
  
  autoviews = # !json autoviews/autoviews
   
  # collate all non-keycode presentations under DEFAULT
  keycodes['DEFAULT'] = item['presentations'].clone
  
  keycodes.each do |keycode,presentations|
    presentations.each do |key, overrides|
        val = {}
        display_fields = fields[overrides['type']]
        if display_fields == nil then display_fields = master_item.keys end
        into = Hash[ master_item.collect do |k,v|
           if not k =~ /^_(?!id)/ and display_fields.include? k then
            overrides.has_key?(k) ? (next k,overrides[k]) : (next k,v)
          end
        end ]
        
        seq = overrides['sequence'] || master_item['sequence'] || 0
        # place "self presenters" directly into the value hash, and retrieve all of their information
        if master_item['_id'] == key then
          val = master_item
          seq = nil 
          val['_id'] = master_item['type']
        else 
          val[overrides['type']] = into 
        end
            
        #begin
        #  condition_tests = conditions[overrides['type']]
        #  results = condition_tests.map do |proc|
        #    proc.call into
        #  end
        #  next if results.include? false
        #rescue => e
        #  log e
        #end
        
        emit([key,keycode,seq],val)
    end
  end
end
