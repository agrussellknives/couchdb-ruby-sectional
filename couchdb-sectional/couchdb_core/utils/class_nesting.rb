require 'active_support/core_ext'

module ClassNesting
  def nesting
    nesteds = self.to_s.split('::')
    res = []
    nesteds.reverse_each do |o| 
      res << nesteds.join('::').constantize
      nesteds.pop
    end
    res
  end
end

class Class
  include ClassNesting
end


