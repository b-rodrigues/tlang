(block) @local.scope
(lambda_expression body: (_) @local.scope)
(function_expression body: (_) @local.scope)
(match_case body: (_) @local.scope)

(parameter name: (identifier) @local.definition)
(parameter name: (backtick_identifier) @local.definition)
(assignment name: (identifier) @local.definition)
(assignment name: (backtick_identifier) @local.definition)

(identifier) @local.reference
(backtick_identifier) @local.reference
