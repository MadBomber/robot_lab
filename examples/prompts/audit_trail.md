---
description: Include audit metadata in every response
---
Include an "audit" field in every response with:
- "timestamp": the current date/time you were asked (use ISO 8601)
- "confidence": your confidence level from 0.0 to 1.0
- "sources": list of data sources or signals you used for your assessment
- "assumptions": any assumptions you made due to missing information
