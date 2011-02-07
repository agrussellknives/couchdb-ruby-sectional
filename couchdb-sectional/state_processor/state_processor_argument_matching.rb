module StateProcessor
  module StateProcessorSection
    # Internal exception raised when no matches are found in the arguments
    # of the on block
    class NoMatchException < StandardError; end

    class MatchProc < Proc; end

    # Simple array subclass which enables us to keep track of matches
    # which should stay in place, and "anywhere" matches that will need
    # to be appended onto the end of the argument list
    class ArgumentMatches < Array
      attr_reader :save
      def initialize
        @save = [] 
        super
      end
      def total_matches
        size + @save.size
      end
    end

    # A placeholder, which like in Erlang means "whatever" it will match whatever
    # argument appears at it's position in the argument list, and discard it.
    # @example Match and Discard the argument
    #   message = [:a, :b, :c]
    #   on _ do |b,c|
    #     [b,c]
    #   end
    #   ->[:b,:c] 
    #
    # When given an argument it will match that argument in any position.
    #   on _(:b) do |a,c|
    #     [a,c]
    #   end
    #   ->[:a,:c]
    #
    # Aliased to both "anything" for the first case and "anywhere" for the second
    # @return [StateProcessorMatch, StateProcessorNoMatch]
    def _(arg=nil)
      return StateProcessorMatch unless arg
      MatchProc.new do |a| 
        next a === arg ? StateProcessorMatch : StateProcessorNoMatch 
      end
    end
    alias :anywhere :_
    alias :anything :_

    # A placeholder, but instead of discarding the matched value appends it to the
    # end of the argument list.
    # @example Match and Save the Argument
    #   message = [:a, :b, :c]
    #   on _! do |b,c,a|
    #     [b,c,a]
    #   end
    #   -> [:b,:c,:a]
    #
    #   on _!(:b) do |a,c,b|
    #     [a,c,b]
    #   end
    #   -> [:a,:c,:b]
    # 
    # @note If arity match is disabled, and you do not have enough arguments in your
    # on block, the "saved" argument is ignored. Unlike unmatched arguments It is not
    # added back on to the command list within the block.
    #
    # Aliased to both "save_anything" for the first case, and save_anywhere for the
    # second.
    def _!(arg=nil)
      return StateProcessorConsume unless arg
      MatchProc.new do |a|
        next a === arg ? StateProcessorConsume : StateProcessorNoMatch 
      end
    end
    alias :save_anywhere :_!
    alias :save_anything :_!

    private
    # Function which performs the matching logic.
    #
    # There should be a better whay to do this than to call it
    # for every "on" clause
    def match_args(matchlist,cmd)
      matches = ArgumentMatches.new 
      
      match_proc = []
      cmd_match = []
      matchlist.each do |m|
        if m.is_a? MatchProc
          match_proc << m
          cmd_match << StateProcessorFunction
        else
          cmd_match << m
        end
      end

      indifferent_match = lambda do |match,arg|
        if match.is_a?(Symbol) || arg.is_a?(Symbol)
          begin
            return arg if arg.to_sym == match.to_sym 
          rescue NoMethodError 
            return false
          end
        else
          return arg if arg == match
        end
      end

      cmd_match.each_with_index do |arg,i|
        next if arg == StateProcessorFunction
        if arg == StateProcessorMatch
          matches << cmd[i] 
        elsif arg == StateProcessorConsume
          matches.save << cmd[i] 
        else
          test = cmd[i]
          f = case arg
            when Array 
              test = test.to_sym rescue test
              arg.include?(test) 
            when Regexp 
              arg.match(test.to_s)
            when Hash
              arg == test
            when Proc
              # this seems a hair tacky
              arg === test
            else
              indifferent_match.call(arg, cmd[i])
          end
          matches << arg if f
        end
      end

      match_proc.each do |mp|
        cmd.each do |c|
          match_action = mp.call(c)
          if match_action == StateProcessorMatch
            matches << c 
          elsif match_action == StateProcessorConsume
            matches.save << c 
          end
        end
      end
      
      raise NoMatchException unless matches.total_matches >= matchlist.size
      matches 
    end
  end
end
