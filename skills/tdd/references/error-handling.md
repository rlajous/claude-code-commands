# Error Handling

| Scenario | Action |
| -------- | ------ |
| Ticket ID not provided | Prompt for ticket ID |
| Ticket not found | Error with suggestion to check ID |
| Tests pass in RED phase | Warn, ask to adjust tests or confirm already fixed |
| Tests fail in GREEN phase | Show errors, retry implementation |
| Max attempts reached | Ask user for guidance |
| Test framework not detected | Ask user for test command |
| No acceptance criteria | Ask user to define test cases |
