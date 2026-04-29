const PREC = {
  pipe: 1,
  formula: 2,
  or: 3,
  and: 4,
  bitOr: 5,
  bitAnd: 6,
  compare: 7,
  add: 8,
  multiply: 9,
  unary: 10,
  call: 11,
  member: 12,
};

module.exports = grammar({
  name: 't',

  extras: $ => [
    $.comment,
    /\s/,
  ],

  word: $ => $.identifier,

  conflicts: $ => [
    [$.list_literal, $.dict_literal],
  ],

  rules: {
    source_file: $ => repeat($._statement),

    comment: _ => token(seq('--', /.*/)),

    _statement: $ => choice(
      $.assignment,
      $.reassignment,
      $.import_statement,
      $.expression_statement,
    ),

    expression_statement: $ => seq($._expression, optional(';')),

    assignment: $ => seq(
      field('name', $._identifier),
      optional(seq(':', field('type', $.type_expression))),
      '=',
      field('value', $._expression),
      optional(';'),
    ),

    reassignment: $ => seq(
      field('name', $._identifier),
      ':=',
      field('value', $._expression),
      optional(';'),
    ),

    import_statement: $ => prec.right(choice(
      seq('import', field('path', $.string), optional(field('names', $.import_list)), optional(';')),
      seq('import', field('package', $._identifier), optional(field('names', $.import_list)), optional(';')),
    )),

    import_list: $ => seq('[', commaSep1($.import_binding), ']'),

    import_binding: $ => choice(
      field('name', $._identifier),
      seq(field('alias', $._identifier), '=', field('name', $._identifier)),
    ),

    _expression: $ => choice(
      $.if_expression,
      $.match_expression,
      $.lambda_expression,
      $.function_expression,
      $.pipeline_expression,
      $.intent_expression,
      $.binary_expression,
      $.broadcast_expression,
      $.unary_expression,
      $.call_expression,
      $.member_expression,
      $.parenthesized_expression,
      $.block,
      $.list_literal,
      $.dict_literal,
      $.empty_dict_literal,
      $.raw_code_block,
      $.shell_command_block,
      $.column_ref,
      $.serializer_id,
      $._identifier,
      $.number,
      $.string,
      $.boolean,
      $.na,
    ),

    parenthesized_expression: $ => seq('(', $._expression, ')'),

    call_expression: $ => prec.left(PREC.call, seq(
      field('function', $._expression),
      '(',
      optional(field('arguments', $.argument_list)),
      ')',
    )),

    argument_list: $ => commaSep1(choice(
      $.named_argument,
      $.ellipsis,
      $._expression,
    )),

    named_argument: $ => choice(
      seq(field('name', $._identifier), choice(':', '='), field('value', $._expression)),
      seq('.', field('name', $.identifier), '=', field('value', $._expression)),
      seq(field('name', $.column_ref), '=', field('value', $._expression)),
      $.dynamic_argument,
    ),

    dynamic_argument: $ => seq('!!', field('name', $._expression), ':=', field('value', $._expression)),

    member_expression: $ => prec.left(PREC.member, seq(
      field('object', $._expression),
      '.',
      field('property', $._identifier),
    )),

    unary_expression: $ => prec.right(PREC.unary, choice(
      seq(field('operator', '-'), field('argument', $._expression)),
      seq(field('operator', '!'), field('argument', $._expression)),
      seq(field('operator', '!!'), field('argument', $._expression)),
      seq(field('operator', '!!!'), field('argument', $._expression)),
    )),

    binary_expression: $ => choice(
      ...[
        ['|>', PREC.pipe],
        ['?|>', PREC.pipe],
        ['~', PREC.formula],
        ['||', PREC.or],
        ['&&', PREC.and],
        ['|', PREC.bitOr],
        ['&', PREC.bitAnd],
        ['==', PREC.compare],
        ['!=', PREC.compare],
        ['<', PREC.compare],
        ['>', PREC.compare],
        ['<=', PREC.compare],
        ['>=', PREC.compare],
        ['in', PREC.compare],
        ['+', PREC.add],
        ['-', PREC.add],
        ['*', PREC.multiply],
        ['/', PREC.multiply],
        ['%', PREC.multiply],
      ].map(([operator, precedence]) => prec.left(precedence, seq(
        field('left', $._expression),
        field('operator', operator),
        field('right', $._expression),
      ))),
    ),

    broadcast_expression: $ => choice(
      ...[
        ['.|', PREC.bitOr],
        ['.&', PREC.bitAnd],
        ['.==', PREC.compare],
        ['.!=', PREC.compare],
        ['.<', PREC.compare],
        ['.>', PREC.compare],
        ['.<=', PREC.compare],
        ['.>=', PREC.compare],
        ['.+', PREC.add],
        ['.-', PREC.add],
        ['.*', PREC.multiply],
        ['./', PREC.multiply],
        ['.%', PREC.multiply],
      ].map(([operator, precedence]) => prec.left(precedence, seq(
        field('left', $._expression),
        field('operator', operator),
        field('right', $._expression),
      ))),
    ),

    if_expression: $ => prec.right(seq(
      'if',
      '(',
      field('condition', $._expression),
      ')',
      field('consequence', $._expression),
      optional(seq('else', field('alternative', $._expression))),
    )),

    lambda_expression: $ => seq(
      '\\',
      optional(field('generics', $.generic_parameter_list)),
      '(',
      optional(field('parameters', $.parameter_list)),
      ')',
      field('body', $._expression),
    ),

    function_expression: $ => seq(
      'function',
      optional(field('generics', $.generic_parameter_list)),
      '(',
      optional(field('parameters', $.parameter_list)),
      ')',
      field('body', $._expression),
    ),

    generic_parameter_list: $ => seq('<', commaSep1($.identifier), '>'),

    parameter_list: $ => choice(
      seq(
        commaSep1($.parameter),
        optional(seq(',', field('variadic', $.ellipsis))),
        optional(seq('->', field('return_type', $.type_expression))),
      ),
      seq(
        field('variadic', $.ellipsis),
        optional(seq('->', field('return_type', $.type_expression))),
      ),
      seq('->', field('return_type', $.type_expression)),
    ),

    parameter: $ => choice(
      seq(field('name', $._identifier), optional(seq(':', field('type', $.type_expression)))),
      seq(field('name', $.column_ref), optional(seq(':', field('type', $.type_expression)))),
    ),

    match_expression: $ => seq(
      'match',
      '(',
      field('value', $._expression),
      ')',
      '{',
      commaSep1($.match_case),
      optional(','),
      '}',
    ),

    match_case: $ => seq(
      field('pattern', $.match_pattern),
      '=>',
      field('body', $._expression),
    ),

    match_pattern: $ => choice(
      $.list_pattern,
      $.error_pattern,
      $.na,
      $.wildcard_pattern,
      $._identifier,
    ),

    wildcard_pattern: _ => '_',

    error_pattern: $ => seq('Error', '{', optional(field('field', $._identifier)), '}'),

    list_pattern: $ => seq(
      '[',
      optional(choice(
        $.list_rest_pattern,
        seq(commaSep1($.match_pattern), optional(seq(',', $.list_rest_pattern))),
      )),
      ']'
    ),

    list_rest_pattern: $ => seq('.', '.', field('name', $._identifier)),

    pipeline_expression: $ => seq(
      'pipeline',
      '{',
      repeat($.pipeline_node),
      '}',
    ),

    pipeline_node: $ => seq(field('name', $._identifier), '=', field('value', $._expression), optional(';')),

    intent_expression: $ => seq(
      'intent',
      '{',
      repeat($.intent_field),
      '}',
    ),

    intent_field: $ => seq(field('name', $._identifier), ':', field('value', $._expression), optional(choice(',', ';'))),

    list_literal: $ => seq('[', optional(commaSep1(choice($.dynamic_argument, $._expression))), optional(','), ']'),

    dict_literal: $ => seq('[', commaSep1(choice($.dict_entry, $.dynamic_argument)), optional(','), ']'),

    empty_dict_literal: _ => seq('[', ':', ']'),

    dict_entry: $ => seq(field('key', $._identifier), ':', field('value', $._expression)),

    block: $ => seq('{', repeat($._statement), '}'),

    raw_code_block: $ => seq('<{', optional($.raw_code_content), '}>'),
    raw_code_content: $ => repeat1(choice(token(prec(1, /[^}]+/)), '}')),

    shell_command_block: $ => seq('?<{', optional($.shell_content), '}>'),
    shell_content: $ => repeat1(choice(token(prec(1, /[^}]+/)), '}')),

    type_expression: $ => prec.right(seq(
      field('name', $.identifier),
      optional(seq('[', commaSep1($.type_expression), ']')),
    )),

    identifier: _ => /[A-Za-z_][A-Za-z0-9_]*/,
    backtick_identifier: _ => token(seq('`', /[^`\n]+/, '`')),
    _identifier: $ => choice($.identifier, $.backtick_identifier),
    column_ref: _ => token(choice(
      seq('$', /[A-Za-z_][A-Za-z0-9_]*/),
      seq('$`', /[^`\n]+/, '`'),
    )),
    serializer_id: _ => token(seq('^', /[A-Za-z_][A-Za-z0-9_]*/)),
    ellipsis: _ => '...',
    number: _ => token(choice(/\d+\.\d+/, /\d+\./, /\d+/)),
    string: _ => token(choice(
      seq('"', repeat(choice(/[^"\\\n]+/, /\\./)), '"'),
      seq("'", repeat(choice(/[^'\\\n]+/, /\\./)), "'"),
    )),
    boolean: _ => choice('true', 'false'),
    na: _ => 'NA',
  },
});

function commaSep1(rule) {
  return seq(rule, repeat(seq(',', rule)), optional(','));
}
