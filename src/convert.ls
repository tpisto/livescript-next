``import * as types from 'babel-types'``

function L
  start: line: it.first_line, column: it.first_column
  end: line: it.last_line, column: it.last_column

* none = [] empty = {} TOP = {} REF = 1 ASSIGN = 2 DECL = 4
function pass => it
node-type = (.constructor.display-name)

function transform node, scope
  node.children .= map (node.)
  next = transform[node-type node]? node, scope
  if next && next != node then transform next else node

function t original, scope
  node = transform original, scope
  convert-node = t[node-type node] || t.unk
  convert-node node, scope
    ..loc = L original
t <<< types
# work around babel/babel#4741
t.objectProperty = (key, value, computed, shorthand) ->
  {type: \ObjectProperty key, value, computed, shorthand}

function merge scope, nested={}
  Object.keys nested .forEach (key) -> scope[key] .|.= nested[key]
  scope

function list-apply whatever, fn => whatever.map? fn or fn whatever

function convert-arg arg, scope, convert-type
  []concat arg .reduce ([nodes, scope] arg) ->
    return [nodes ++ arg, scope] unless arg
    node = convert-type t arg, scope
    * nodes ++ node, merge scope, node.scope
  , [[] scope]
    ..0 = ..0.0 unless arg?reduce

function reduce children, upper, types
  children.reduce ([args, scope] arg, index) ->
    [sub-args, next-scope] =
      convert-arg arg, scope, types[index] || expr
    * args ++ [sub-args] next-scope
  , [[] Object.create upper]

function define {types=none, input=pass, output=pass, params=pass, build}
=> (node, upper) ->
  [nodes, scope] = output _, upper
  <| reduce node.children, _, types
  <| input upper, node
  (t[build] ...params nodes, node) <<< {scope}

function expand-pair
  if it.type == \Identifier then [[it, it]] else it

function list
  result = it.properties?map ->; * it.key, list it.value
  result || it

function change-name node, name => node <<< constructor: display-name: name

# Module

is-import = (.value == \this)
function is-module {left} scope
  (is-import left or left.verb == \out) && scope.__proto__ == TOP

transform.Import = (node, scope) ->
  if is-module node, scope then change-name node, \Module
  else node <<< op: \objectImport + (node.all || '')

function pack-export => [;* void it]
function pack-import => it.map ([source, name]) -> ;* source, [[name]]
function specify-import alias, name
  if alias then t.importSpecifier alias, name
  else t.importDefaultSpecifier name

function module-declare extended, base, declare, specify, pack
  extended.concat if base.length > 0 then pack base else []
  .map ([from, names]) ->
    source = string-literal that if from
    declare _, source <| names.map ([name, alias]) -> specify alias, name

function module-io {left, right} scope
  items = list expand-pair t right, scope
  base = items.filter -> !it.1.map
  extended = items.filter (.1.map)
  t.blockStatement module-declare extended, base, ...if is-import left
    * t.importDeclaration, specify-import, pack-import
  else
    * t.exportNamedDeclaration.bind void void; t.exportSpecifier, pack-export

function map-values object, value
  Object.keys object .reduce _, {} <| (result, key) ->
    result[key]? = value object[key]
    result

# Assign

function mark-lval => if it.value != \void then it <<< lval: true else null

NONE = {+void, +null}
transform.Assign = (node, scope) ->
  if \Existence == node-type node.children.0
    node.children.0 .= it
    node.soak = \?
  switch
  | NONE[node.left.value] => node.right
  | node.op == \= => node <<< left: mark-lval node.left
  | _ => node <<< op: node.op - \:

function transform-lval index=0 => (node, scope) ->
  return node unless node.lval
  node.children[index] = list-apply node.children[index], mark-lval
  node

<[Arr Obj Splat Existence]>forEach -> transform[it] = transform-lval!
transform.Binary = (node, scope) ->
  return unless node.lval
  next = change-name _, \Assign <| transform-lval! node, scope
  next <<< op: \=
transform.Prop = transform-lval 1

function convert-variable
  name = it.value || it.name
  variable = t.id name
  type = if it.lval then DECL else if it.value then REF
  if type then variable <<< scope: (name): type
  else variable

t.assignment = (op, left, right) ->
  t.assignmentExpression op, (lval left), right

t\<?= = t\>?= = (op, left, right) ->
  t.assignment \= left, t[op.slice 0 2] void left, right

# Infix

transform.Parens = (node, scope) -> node.it

convert-infix = define build: \infixExpression params: infix-params
function infix-params args, node => [node.op] ++ args ++ node<[logic soak]>

t.BINARY_OPERATORS.forEach -> t[it] = t.binaryExpression
t.LOGICAL_OPERATORS.forEach -> t[it] = t.logicalExpression
t.NUMBER_BINARY_OPERATORS.concat ['' \+] .forEach -> t"#it=" = t.assignment

function wrap-condition logic, target, result
  t[logic]? logic, target, result or result

function wrap-soak type, target, result
  if type then t\? type, target,, result else result

t.infix-expression = (op, left, right, logic, soak) ->
  op .= replace /\.(.)\./ \$1
  wrap-soak soak, right,
  wrap-condition logic, left, if right then t[op] op, left, right
  else t.unaryExpression op, left

condition =
  \? : -> t.binaryExpression \!= it, t.nullLiteral!
  Call: -> t.binaryExpression \==,
    t.unaryExpression \typeof it
    t.valueToNode \function

t\<? = (, ...args) -> helpers.min args
t\>? = (, ...args) -> helpers.max args
t.existence = condition\?
t\? = (logic, target, other, next, alt) ->
  check = condition[logic] || t.existence
  t.conditionalExpression (check target, alt || other),
    next || target, other || literals.void

t.object-import = (, ...args) -> helpers.assign args

# Chain

transform.Chain = ({head, tails}) ->
  tails.reduce _, head <| (tree, node) ->
    node <<< base: tree, children: [\base] ++ node.children

function chain-params args, node => [node-type node; node.soak] ++ args
convert-chain = define build: \chain params: chain-params
chain-types = Index: \memberExpression Call: \callExpression
t.chain = (type, soak, ...args) ->
  args.push args.1.type != \Identifier if type == \Index
  wrap-soak soak && type, args.0, t[chain-types[type]] ...args

# Block

function declare names
  t.variableDeclaration \let names.map -> t.variableDeclarator t.id it

function close-scope upper, scope
  to-declare = -> (upper[it].|.0) < DECL && scope[it] >= DECL
  Object.keys scope
    declared = ..filter to-declare
    referenced = ..filter -> !to-declare it
  declarations = declare declared if declared.length > 0
  * declarations, referenced

function make-block [[body] scope] upper
  [declarations, referenced] = close-scope upper, scope
  body = body.reduce (body, node) ->
    body ++= if t.isBlock node then node.body else node
  , if declarations then [that] else []
  * [body] scope = {[k, scope[k]] for k in referenced}

function omit-declared => it if it < DECL

# Function

transform.Fun = (node, _) -> node <<< params: node.params.map mark-lval

function convert-return node
  [..., last] = node.body
  if last && !t.isReturnStatement last
    node.body[*-1] = t.returnStatement expr last
  node

function make-function [[params, block]]
  if params.length == 0 && block.scope.it
    params = [t.id \it]
    block.scope.it = DECL
  * * params, convert-return block
    scope = map-values block.scope, omit-declared

# Switch

function expand-cases => it.map -> t.switchCase it, []

function switch-params [topic, cases, other=literals.void]
  test = if topic then -> t.binaryExpression \== that, it
  else pass
  last = expr other
  [cases.reduce-right _, last <| (chain, {test: {elements} consequent}) ->
    t.conditionalExpression do
      elements.map test .reduce helpers.or
      if consequent.length > 0 then t.sequenceExpression consequent.map expr
      else literals.void
      chain]

function case-params [tests, {body}]
  * t.arrayExpression tests; body

#Child types

function lval
  return it if t.isLVal it
  it <<< type:
    | t.isSpreadElement it => \RestElement
    | _ => it.type.replace \Expression \Pattern

function derive adapt => (node) ->
  (adapt node) <<< node{loc}
    ..scope = merge node.scope, ..scope

statement = derive ->
  | t.toStatement it, true => that
  | t.isExpression it => t.expressionStatement it
  | _ => it

function wrap-expression node => t.doExpression t.blockStatement [node]

expr = derive (node) ->
  | t.isExpression node or t.isSpreadElement node => node
  | node.expression => that
  | t.isFunction node => node <<< type: \FunctionExpression
  | node.body?length == 1 => expr node.body.0
  | _ => wrap-expression node

literals = <[this arguments eval]>reduce (data, name) ->
  data <<< (name): t.identifier name
, void: t.unaryExpression \void t.valueToNode 8

string-literal = derive ->
  | it.type == \StringLiteral => it
  | it.name => t.stringLiteral that

property = derive ->
  | it.type == \ObjectProperty => it
  | t.isSpreadElement it => it <<< type: \SpreadProperty
  | it.type == \AssignmentExpression =>
    t.objectProperty it.left, it <<< type: \AssignmentPattern, false true
  | _ => t.objectProperty ...property-params [it, it]

function property-params [key, value]
  * key, value
    computed = key.type != \Identifier && key.type != \Literal
    shorthand = key == value

t <<<
  id: -> t.identifier it
  unk: -> throw "Unimplemented node type: #{node-type it}"

  Literal: -> literals[it.value] or t.valueToNode eval it.value
  Key: convert-variable, Var: convert-variable

  Arr: define build: \arrayExpression
  Obj: define build: \objectExpression types: [property]
  Prop: define build: \objectProperty params: property-params

  Module: module-io
  Index: convert-chain, Call: convert-chain
  Unary: convert-infix, Binary: convert-infix, Assign: convert-infix
  Import: convert-infix, Existence: define build: \existence
  Splat: define build: \spreadElement

  Block: define do
    build: \blockStatement types: [statement] input: ->
      if it == TOP then it else {}
    output: make-block

  Return: define build: \returnStatement
  Fun: define do
    build: \functionExpression types: [lval, statement]
    input: (, node) -> if node.params.length == 0 then it: DECL else {}
    output: make-function
    params: (args, node) -> [t.id node.name || ''] ++ args

  If: define build: \ifStatement types: [void statement, statement]
  Switch: define build: \expressionStatement \
    types: [pass, pass, pass] params: switch-params
  Case: define build: \switchCase \
    types: [pass, pass] params: case-params

function make-helper name, method
  fn = t.memberExpression (t.id name), t.id method
  -> t.callExpression fn, it

helpers =
  assign: make-helper \Object \assign
  min: make-helper \Math \min
  max: make-helper \Math \max
  or: (a, b) -> t.logicalExpression \|| a, b

function convert root
  program = t root, TOP
    ..type = \Program
  t.file program, [] []
    ..loc = program.loc

``export default convert``
