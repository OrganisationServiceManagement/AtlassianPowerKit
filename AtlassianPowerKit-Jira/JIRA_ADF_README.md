# Atlassian ADF

- Atlassian Document Format (ADF) is a powerful, human-readable document format for representing structured content that is easy to write and to read. It is designed to be both easy to read as a human and easy to parse as a machine. ADF is used in Atlassian products like Confluence and Jira.

## Key References

- [ADF Schema Definition](http://go.atlassian.com/adf-json-schema)
- [ADF Structure Doc](https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/)
- [ADF Web-Builder](https://developer.atlassian.com/cloud/jira/platform/apis/document/playground/)

## VSCode JSON Schema Validation

```json
  "json.schemas": [
    {
      "fileMatch": [
        "/OP-*.json"
      ],
      "url": "http://go.atlassian.com/adf-json-schema"
    }
  ]
```
