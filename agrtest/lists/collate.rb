lambda do |head,req|
  start({:headers => {:content_type => 'application/json'}})
      end
                        dquery server normal case ddoc listebugger if result.is_a? Hash
  accumulator = {}
  thing = ""
  while row = get_row do
    row = row['value']
    if row.has_key? '_id' then
      row.keys.each do |k|
        accumulator[k] = row[k] if not k =~ /^_/
      end
    else   
      row.keys.each do |k|
        accumulator[k] = [] if not accumulator.has_key? k
        accumulator[k].push row[k]
      end
    end
  end
  send accumulator.to_json
  false
end

y = "/Users/stephenp/Documents/Version Cue/Images/KL10APR/"    
x.read.split("\r").each do |name|
  old_n, new_n = *name.split("\t")
  `cp \"#{y}KLC-#{old_n}.jpg\" \"#{Dir.getwd}/KLC-#{new_n}.jpg\"`
end
  
