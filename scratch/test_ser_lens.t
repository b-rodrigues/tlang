l = col_lens("b")
ser = serialize(l)
print("Serialized lens:")
print(ser)

l2 = deserialize(ser)
print("Deserialized lens:")
print(l2)

d = [a: 1, b: 2]
print("Try to use deserialized lens:")
print(get(d, l2))
