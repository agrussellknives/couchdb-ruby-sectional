require_relative '../couchdb-sectional/state_processor'

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

      class InternalSwitchStateAgainAndAgain
        include StateProcessor
        include StateProcessor::StateProcessorWorker
        def nested_test2
          return 'nested test 2'
        end
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

    on :hello do |a|
      send IndependentState, [:hi,a]  
      answer :ok do
        on :who do
          n = send IndependentState, [:who]
          return n
        end
      end
    end

    on :hello_again do |a|
      send IndependentState, [:hi_again, a], deferred: true do |n|
        sleep .5 
        @n = n 
      end
      return @n
    end

    on :hello_again_response do |a|
      return @n
    end

    on :switch_state do
      switch_state InternalSwitchState do #should look up constants in worker context
        commands do #should be run in processor context
          on :okay do
            return 'okay'
          end

          on :nest_test do
            switch_state InternalSwitchStateAgain do
              commands do
                return_after do
                  on :nested_test
                end
               
                switch_state InternalSwitchStateAgainAndAgain do
                  commands do
                    return_after do
                      on :nested_test2
                    end

                    on :pass_test do
                      answer "pass_test"
                    end

                    on :pass_tested2 do
                      return "test pasted"
                    end
                  end
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

    on :again_again do
      switch_state InternalSwitchStateAgainAndAgain do
        commands do
          on :nested_test3 do
            return "uh oh, bad mojo" 
          end
        end
      end
    end

    on :do_not_switch do
      return 'fine'
    end

    on :external_switch do
      switch_state ExternalSwitchState
      return "i shouldn't be seen"
    end

    on :external_top do
      switch_state ExternalSwitchState, top: true
      return "fall through"
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

  protocol RubyPassThroughProtocol

  commands do
    on :fall_through do
      "fine then"
    end

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
      answer "not_okay"
    end

  end
end

class IndependentState
  include StateProcessor
  include StateProcessor::StateProcessorWorker

  commands do
    on :hi do |a|
      @a = a 
    end

    on :hi_again do |n|
      return "hello from #{n}"
    end

    on :who do
      return @a
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

    it "should switch to a deeply nested subcomponent" do
      out = @co << [:switch_state, :nest_test, :nested_test2]
      out.should == 'nested test 2'
    end

    it "shouldn't be able to define new commands" do
      lambda { @co << [:again_again, :nested_test3] }.should raise_error (
        StateProcessor::StateProcessorExceptions::StateProcessorDoesNotRespond)
    end
    
    it "should however, be able to execute the original ones" do
      out = @co << [:again_again, :nested_test2]
      out.should == 'nested test 2'
    end

    it "component resume should work predictably" do
      out = @co << [:switch_state, :nest_test, :pass_test]
      out.should == "pass_test"
      out = @co << [:pass_tested2]
      out.should == "test pasted"
    end

    it "should resume even if it's arrived at by a different path" do
      out = @co << [:again_again, :pass_test]
      out.should == "pass_test"
      out = @co << [:pass_tested2]
      out.should == "test pasted"
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
    out = @co << [:reset_top,:end_this,:post_reset]
    out.should == "post_reset"
  end

  describe "submessages to independents" do
    
    before :all do 
      @eco = EventedCommObject.new AdvancedStateProcessor
    end

    it "it should be able to pass a 'submessage' to other states" do
      out = @eco << [:hello,"bob"]
      out.should == :ok
      out = @eco << [:who]
      out.should == "bob"
    end

    it "should be able to async pass a 'submessage'" do
      debugger
      out = @eco << [:hello_again,"bob"]
      out.should == nil
      out = @eco << [:hello_again_response]
      out.should == "hello from bob"
    end

    after :all do
      # kill the event machine we just started
      EM.next_tick do
        EM.stop 
      end
      @eco.kill_thread
    end
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

    it "should fall of the end of the external if top is not reset" do
      out = @co << [:external_switch,:fall_through]
      out.should == "fine then"
    end

    it "will return to caller if top is reset" do
      out = @co << [:external_top, :fall_through]
      out.should == "fall through"
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
    
