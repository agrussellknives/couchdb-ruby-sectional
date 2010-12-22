# simple aspect module

class Module 
  def define_aspect aspect_name, &definition
    self.class.instance_eval do
      define_method(:"add_#{aspect_name}") do |*method_names|
        method_names.each do |method_name|
          original_method = instance_method(method_name)
          define_method(method_name, &(definition[method_name,original_method]))
        end
      end
    end
  end
end

class Class
  define_aspect :logging do |method_name, original_method|
    lambda do |*args, &blk|
      STDERR << "Called #{method_name} with #{args}\n"
      original_method.bind(self).call(*args,&blk)
    end
  end
end
