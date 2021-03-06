require 'java'

module NotesParser

  def self.parse(note, base_uri)
    cleaned_note = org.jsoup.Jsoup.clean(note, org.jsoup.safety.Whitelist.relaxed.addTags("emph", "lb").addAttributes("emph", "render"))

    document = org.jsoup.Jsoup.parse(cleaned_note, base_uri, org.jsoup.parser.Parser.xmlParser())

    # replace lb with br
    document.select("lb").tagName("br")

    # tweak the emph tags
    document.select("emph").each do | emph |
      # make all emph's a span
      emph.tagName("span")

      # <emph> should render as <em> if there is no @render attribute. If there is, render as follows:
      if emph.attr("render").blank?
        emph.attr("class", "emph render-none")

      # render="nonproport": <code>
      elsif emph.attr("render") === "nonproport"
        emph.attr("class", "emph render-#{emph.attr("render")}")
        emph.tagName("code")
        emph.removeAttr("render")

      # set a class so CSS can style based on the render value
      else
        emph.attr("class", "emph render-#{emph.attr("render")}")
        emph.removeAttr("render")
      end
    end

    document.toString()
  end

end