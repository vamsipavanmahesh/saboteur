class BranchChoice
  def choose(flag)
    flag ? 10 : 20
  end

  def nested(outer, inner)
    outer ? (inner ? 30 : 40) : 50
  end

  def both(flag)
    flag ? 60 : 70
  end

  def short(flag)
    flag && 80
  end
end
