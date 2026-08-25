# Error Handling

| Scenario                    | Action                                         |
| --------------------------- | ---------------------------------------------- |
| Not on development branch   | Instruct to checkout and pull                  |
| Behind remote               | Instruct to pull latest                        |
| Release branch exists       | Ask to delete and recreate                     |
| No commits to release       | Warn nothing to release                        |
| Version bump fails          | Show error, manual instructions                |
| Merge conflicts             | Show conflict resolution instructions          |
| `gh` not authenticated      | Provide auth instructions                      |
