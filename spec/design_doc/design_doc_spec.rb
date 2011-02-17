module EmitsTwo
  def emit_two
    2
  end
end

class TestDesignDoc < DesignDocumentBase

  module ViewLibrary
    module BigString
      def makebigstring p
        str = "a"
        p.times do
          str << str.dup
        end
      end
    end
    module Boom
      def boom
        "ok"
      end
    end
  end

  module AllLibraries
    module ToUpper
      def to_upper_mine p
        p.upcase
      end
    end
  end

  class AllDocsTwice < View
    def map doc
      emit(doc.integer, nil)
      emit(doc.integer, nil)
    end
  end

  class NoDocs < View
    def map doc
      emit nil
    end
  end

  class SingleDoc < View
    def map doc
      if doc[:_id] == "1" then
        emit 1, nil
      end
    end
  end

  class Summate < View
    def map doc
      emit doc[:integer], doc[:integer]
    end

    def reduce k,v
      return v.sum
    end
  end

  class Summate2 < View
    def map doc
      emit doc[:integer], doc[:integer]
    end
    def reduce k,v
      return v.sum
    end
  end

  class HugeSrcAndResults < View
    def map doc
      include BigString
      if doc[:_id] == "1" then
        emit makebigstring.call(16),nil
      end
    end
    def reduce k,v
      return makebigstring.call(16)
    end
  end

  class CantImportOtherStuff < View
    def map doc
      include Base64
      emit nil,Base64.encode(doc.to_s)
    end
  end

  class IncludesOnly < View
    # this won't work.  failing tests
    include EmitsTwo
    def map doc
      emit emit_two, nil
    end
  end

  class Library < View
    def map doc
      emit boom, nil
    end
  end
  
  module Shows
    def simple
      return 'ok'
    end

    def requirey
      include ToUpper
      'ok'.to_upper_mine
    end
  end

  module Lists
    def whatever
      # list functions
    end

    def also_whatever
      # list functions
    end
  end

  module Filters
    def okay
      return true
    end

    def not_okay
      return false
    end
  end

  def validate_doc_update newdoc, olddoc, userctx, secobj
    return true
  end

  rewrites do
    rewrite do
      from ""
      to "index.html"
      method :get
    end
    rewrite do
      from "/a/b"
      to "/some/"
    end
    rewrite do
      from "/a/b"
      to "/some/:var"
    end
    rewrite do
      from "/a"
      to "/some/*"
    end
    rewrite do
      from "/a/:foo/*"
      to "/some/:foo/*"
    end
    rewrite do
      from "/a/:foo"
      to "/some"
      query :k => "foo"
    end
    rewrite do
      from "/a"
      to "some/:foo"
    end
  end

  attachments do
    #inline data attachment
    filename "foo.txt" do
      content_type 'text/plain'
      data 'VGhpcyBpcyBhIGJhc2U2NCBlbmNvZGVkIHRleHQ=' 
    end
    filename "test.jpg"
  end
end

DOCS = <<JSON
[ 
  {
    '_id':'doc1'
    'integer':1
  },
  {
    '_id':'doc2'
    'integer':2
  },
  {
    '_id':'doc3'
    'integer':3
  }
]
JSON
