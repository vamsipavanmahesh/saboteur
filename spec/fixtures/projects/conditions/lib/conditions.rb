class Conditions
  def checked(value)
    value ? 1 : 2
  end

  def unchecked(value)
    if value
      1
    else
      2
    end
  end
end
