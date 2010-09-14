lambda do |keys, values, rereduce|
  return values.size unless rereduce
  return values.inject(0) { |sum,item| sum + item }
end