# simple aspect module

class Module
  def self.define_aspect aspect_name, &definition
    define_method(:"add_#{aspect_name}") do |*method_names|
      method_names.each do |method_name|
        original_method = instance_method(method_name)
        define_method(method_name, &(definition[method_name,original_method]))
      end
    end
  end
end
