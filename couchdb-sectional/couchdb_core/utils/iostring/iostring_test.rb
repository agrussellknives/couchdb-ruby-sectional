require_relative './lib/iostring'

io = IOString.new('okay')
io.close_write
io.read

