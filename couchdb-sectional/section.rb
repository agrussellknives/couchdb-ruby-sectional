require_relative 'thin_adapter'

class Section
  include StateProcessor
  include StateProcessorWorker
end

class SectionalApp
  include StateProcessor
  include StateProcessorWorker
  protocol HTTPApplication
  include SectionalHTTPApplication
end
