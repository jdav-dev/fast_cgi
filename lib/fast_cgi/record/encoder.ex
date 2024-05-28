defprotocol FastCGI.Record.Encoder do
  @moduledoc false

  def to_iodata(data)
end

defimpl FastCGI.Record.Encoder, for: Atom do
  def to_iodata(atom), do: to_string(atom)
end

defimpl FastCGI.Record.Encoder, for: BitString do
  def to_iodata(bitstring), do: bitstring
end

defimpl FastCGI.Record.Encoder, for: List do
  def to_iodata(list), do: for(item <- list, do: FastCGI.Record.Encoder.to_iodata(item))
end
