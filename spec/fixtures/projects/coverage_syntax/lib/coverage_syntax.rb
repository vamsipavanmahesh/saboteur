class CoverageSyntax
  def message(name)
    <<~TEXT
      Hello #{name}!
    TEXT
    "Hello #{name}!\n"
  end

  def route(event)
    case event
    in {type: "charge"}
      :charged
    in {type: "refund"}
      :refunded
    else
      :unknown
    end
  end
end
