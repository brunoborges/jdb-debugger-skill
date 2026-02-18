# Sample App — JDB Testing Application

A simple console application with **intentional bugs** for testing the `jdb-agentic-debugger` plugin.

## Build & Run

```bash
cd sample-app

# Compile
javac -g -d out WarningAppTest.java
javac -g -d out ConsoleAppTest.java

# Run normally
java -cp out com.example.WarningAppTest
java -cp out com.example.ConsoleAppTest BASIC

# Run with JDWP for remote debugging
java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005 -cp out com.example.WarningAppTest
java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005 -cp out com.example.ConsoleAppTest BASIC
```

## Sample Apps

### WarningAppTest (Swing GUI)

A Swing application with **intentional bugs** for testing the `jdb-agentic-debugger` plugin.

#### Intentional Bugs

| # | Bug | How to Trigger | Expected Symptom |
|---|-----|----------------|------------------|
| 1 | `NullPointerException` | Click "Show Warning" with empty input | `processMessage` returns `null`, then `showWarning` passes it to `JOptionPane` |
| 2 | Off-by-one counter | Click "Show Warning" with any text | Counter always shows one less than actual |
| 3 | `NullPointerException` after clear | Click "Clear History", then "Show Warning" | `warningHistory` is set to `null` instead of cleared |
| 4 | `StringIndexOutOfBoundsException` | Enter text shorter than 3 characters (e.g., "Hi") | `substring(0, 3)` on a 2-char string |

## Debugging Exercises

### WarningAppTest

Use the `jdb-debugger` skill to:

1. **Catch the NPE**: `catch java.lang.NullPointerException`, then trigger bug #1
2. **Watch the counter**: Set `stop at com.example.WarningAppTest:50` and inspect `warningCount`
3. **Find the memory leak**: Set breakpoint in `clearHistory()` and inspect `warningHistory`
4. **Catch bounds error**: `catch java.lang.StringIndexOutOfBoundsException`, enter "Hi"

### ConsoleAppTest

A simple console application that looks up discount percentages by membership tier (`BASIC`, `PREMIUM`, `VIP`). Defaults to 0% for unknown tiers.

```bash
java -cp out com.example.ConsoleAppTest BASIC      # Discount = 5%
java -cp out com.example.ConsoleAppTest VIP        # Discount = 30%
java -cp out com.example.ConsoleAppTest UNKNOWN    # Discount = 0%
java -cp out com.example.ConsoleAppTest            # Usage message
```

Use the `jdb-debugger` skill to:

1. **Inspect the map**: Set `stop at com.example.ConsoleAppTest:20` and inspect the `discounts` map
2. **Trace the lookup**: Step through the `discounts.get(tier)` call and inspect `discount`
3. **Test null handling**: Run with an unknown tier and verify the null check at line 22
