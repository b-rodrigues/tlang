-- Test NSE (Non-Standard Evaluation) with $column syntax

-- Create a simple dataset
df = read_csv("examples/data/simple.csv")

-- Test select with NSE
print("Testing select with NSE:")
result1 = df |> select($name, $age)
print(result1)

-- Test arrange with NSE
print("\nTesting arrange with NSE:")
result2 = df |> arrange($age)
print(result2)

-- Test group_by with NSE
print("\nTesting group_by with NSE:")
result3 = df |> group_by($dept)
print(result3)

-- Test combining NSE operations
print("\nTesting combined NSE operations:")
result4 = df 
  |> select($name, $age, $dept)
  |> arrange($age, "desc")
  |> group_by($dept)
print(result4)

print("\n✅ NSE tests completed!")
