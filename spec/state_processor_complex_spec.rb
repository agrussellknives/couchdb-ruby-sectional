require_relative '../couchdb-sectional/eventmachine/state_processor'

require_relative 'helpers'

class AdvancedStateProcessor

  class InternalSwitchState 
    include StateProcessor
    include StateProcessor::StateProcessorWorker

    def worker_test
      return "worker test"
    end

    class InternalSwitchStateAgain
      include StateProcessor
      include StateProcessor::StateProcessorWorker
      def nested_test
        return 'nested test'
      end
    end
  end

  class NewTop
    include StateProcessor
    include StateProcessor::StateProcessorWorker
  end

  include StateProcessor
  include StateProcessor::StateProcessorWorker

  protocol RubyPassThroughProtocol

  commands do
    on :switch_state do
      switch_state InternalSwitchState do
        commands do
          on :okay do
            return 'okay'
          end

          on :nest_test do
            switch_state InternalSwitchStateAgain do
              commands do
                return_after do
                  on :nested_test
                end
              end
            end
          end

          return_after do
            on :worker_test
          end
        end
      end
    end

    on :do_not_switch do
      return 'fine'
    end

    on :external_switch do
      switch_state ExternalSwitchState
    end

    on :reset_top do
      @nt = switch_state NewTop, top: true do
        commands do
          on :end_this do
            return "bob"
          end
        end
      end
    end

    on :reset_top, :end_this, :post_reset do
      return "post_reset"
    end

    on :reset_top, :end_this, :new_top do
      return @nt, "okay"
    end
  end
end

class ExternalSwitchState
  include StateProcessor
  include StateProcessor::StateProcessorWorker

  def worker_test
    return "external worker test"
  end

  commands do
    on :okay do
      return "external"
    end

    return_after do
      on :worker_test
    end
    
    on :now_okay do
      return "now okay"
    end

    on :not_okay do
      pass "not_okay"
    end
  end
end



describe AdvancedStateProcessor, "subcomponent matching" do

  before do
    @co = CommObject.new AdvancedStateProcessor
  end

  describe "subcomponent" do
    it "should switch state to subcomponent" do
      out = @co << [:switch_state,:okay]
      out.should == 'okay'
    end

    it "should switch state to a nested subcomponent" do
      out = @co << [:switch_state, :nest_test, :nested_test]
      out.should == 'nested test'
    end

    it "should execute in the original state in return" do
      out = @co << [:switch_state, :okay]
      out.should == 'okay'
      out = @co << [:do_not_switch]
      out.should == 'fine'
    end

    it "should have changed the worker" do
      out = @co << [:switch_state, :worker_test]
      out.should == "worker test"
    end
  end

  it "it should be able to reset top" do
    out = @co << [:reset_top,:end_this]
    out.should == "bob"
    debugger

    out = @co << [:reset_top,:end_this,:post_reset]
    out.should == "post_reset"
  end

  it "should accumulate the results of subcomponents if you ask it to" do
    out = @co << [:reset_top, :end_this,:new_top]
    out.should == ["bob","okay"]
  end

  describe "independent component" do
    it "should switch state to independent component" do
      out = @co << [:external_switch,:okay]
      out.should == 'external'
    end

    it "should switch state to independent component and stay there" do
      out = @co << [:external_switch,:not_okay]
      out.should == "not_okay"
      out = @co << [:now_okay]
      out.should == "now okay"
    end

    it "should swithc the worker in independents too" do
      out = @co << [:external_switch, :worker_test]
      out.should == "external worker test"
    end
  end
end
    
