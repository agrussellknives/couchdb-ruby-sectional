require_relative 'thin_adapter'

class Section
  include StateProcessor
  include StateProcessorWorker
end

class SectionalApp
  include StateProcessor
  include StateProcessorWorker
  include SectionalHTTPApplication
  protocol HTTPApplication
end
