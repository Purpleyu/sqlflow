%{
package parser

import (
	"fmt"
	"log"
	"strings"
	"sync"
)

/* expr defines an expression as a Lisp list.  If len(val)>0,
   it is an atomic expression, in particular, NUMBER, IDENT,
   or STRING, defined by typ and val; otherwise, it is a
   Lisp S-expression. */
type Expr struct {
	Type  int
	Value string
	Sexp  ExprList
}

type ExprList []*Expr

type ConstraintExpr struct {
	expr *Expr
	groupby string
}

type ConstraintExprList []*ConstraintExpr

/* construct an atomic expr */
func atomic(typ int, val string) *Expr {
	return &Expr{
		Type:  typ,
		Value: val,
	}
}

/* construct a funcall expr */
func funcall(name string, oprd ExprList) *Expr {
	return &Expr{
		Sexp: append(ExprList{atomic(IDENT, name)}, oprd...),
	}
}

/* construct a unary expr */
func unary(typ int, op string, od1 *Expr) *Expr {
	return &Expr{
		Sexp: append(ExprList{atomic(typ, op)}, od1),
	}
}

/* construct a binary expr */
func binary(typ int, od1 *Expr, op string, od2 *Expr) *Expr {
	return &Expr{
		Sexp: append(ExprList{atomic(typ, op)}, od1, od2),
	}
}

/* construct a variadic expr */
func variadic(typ int, op string, ods ExprList) *Expr {
	return &Expr{
		Sexp: append(ExprList{atomic(typ, op)}, ods...),
	}
}

type SQLFlowSelectStmt struct {
	Extended  bool
	Train     bool
	Predict   bool
	Explain   bool
	Evaluate  bool
	Run       bool
	Optimize  bool
	ShowTrain bool

	StandardSelect
	TrainClause
	PredictClause
	ExplainClause
	EvaluateClause
	OptimizeClause
	ShowTrainClause
	RunClause
}

type StandardSelect struct {
	origin string
}

type TrainClause struct {
	Estimator       string
	TrainAttrs      Attributes
	Columns         columnClause
	Label           string
	TrainUsing      string
	Save            string
}

/* If no FOR in the COLUMN, the key is "" */
type columnClause map[string]ExprList

type Attributes map[string]*Expr

type PredictClause struct {
	PredAttrs Attributes
	Model     string
	// FIXME(tony): rename into to predTable
	Into string
}

type ExplainClause struct {
	ExplainAttrs Attributes
	TrainedModel string
	Explainer    string
	ExplainInto  string
}

type EvaluateClause struct {
	EvaluateAttrs Attributes
	// Fields needed by evaluate clause
	ModelToEvaluate string
	EvaluateLabel string
	EvaluateInto  string
}

type RunClause struct {
	ImageName       string
	Parameters      []string
	OutputTables    []string
}

type OptimizeClause struct {
	// Direction can be MAXIMIZE or MINIMIZE
	Direction string
	Objective *Expr
	Constrants ConstraintExprList
	OptimizeAttrs Attributes
	Solver string
	OptimizeInto string
}

type ShowTrainClause struct {
	ModelName string
}

var parseResult *SQLFlowSelectStmt

func attrsUnion(as1, as2 Attributes) Attributes {
	for k, v := range as2 {
		if _, ok := as1[k]; ok {
			log.Panicf("attr %q already specified", as2)
		}
		as1[k] = v
	}
	return as1
}
%}

%union {
  val string  /* NUMBER, IDENT, STRING, and keywords */
  flds ExprList
  tbls []string
  expr *Expr
  expl ExprList
  ctexp  *ConstraintExpr
  ctexpl ConstraintExprList
  atrs Attributes
  eslt SQLFlowSelectStmt
  slct StandardSelect
  tran TrainClause
  colc columnClause
  labc string
  infr PredictClause
  expln ExplainClause
  evalt EvaluateClause
  runc  RunClause
  optim OptimizeClause
  shwtran ShowTrainClause
}

%type  <eslt> sqlflow_select_stmt
%type  <tran> train_clause
%type  <shwtran> show_train_clause
%type  <colc> column_clause
%type  <labc> label_clause
%type  <infr> predict_clause
%type  <expln> explain_clause
%type  <evalt> evaluate_clause
%type  <runc> run_clause
%type  <optim> optimize_clause
%type  <val> optional_using
%type  <expr> expr funcall column
%type  <expl> ExprList pythonlist columns
%type  <ctexp> ConstraintExpr
%type  <ctexpl> ConstraintExprList
%type  <atrs> attr
%type  <atrs> attrs
%type  <tbls> stringlist, identlist

%token <val> SELECT FROM WHERE LIMIT TRAIN PREDICT EXPLAIN EVALUATE RUN MAXIMIZE MINIMIZE CONSTRAINT WITH COLUMN LABEL USING INTO FOR AS TO SHOW GROUP BY CMD
%token <val> IDENT NUMBER STRING

%left <val> AND OR
%left <val> '>' '<' '=' '!' GE LE NE
%left <val> '+' '-'
%left <val> '*' '/' '%'
%left <val> NOT
%left <val> POWER  /* think about the example "NOT base ** -3" */
%left <val> UMINUS

%%

sqlflow_select_stmt
: train_clause end_of_stmt {
	parseResult = &SQLFlowSelectStmt{
		Extended: true,
		Train: true,
		TrainClause: $1}
  }
| predict_clause end_of_stmt {
	parseResult = &SQLFlowSelectStmt{
		Extended: true,
		Predict: true,
		PredictClause: $1}
  }
| explain_clause end_of_stmt {
	parseResult = &SQLFlowSelectStmt{
		Extended: true,
		Explain: true,
		ExplainClause: $1}
  }
| evaluate_clause end_of_stmt {
	parseResult = &SQLFlowSelectStmt{
		Extended: true,
		Evaluate: true,
		EvaluateClause: $1}
  }
| run_clause end_of_stmt {
	parseResult = &SQLFlowSelectStmt{
		Extended: true,
		Run: true,
		RunClause: $1}
  }
| optimize_clause end_of_stmt {
	parseResult = &SQLFlowSelectStmt{
		Extended: true,
		Optimize: true,
		OptimizeClause: $1}
}
| show_train_clause end_of_stmt {
	parseResult = &SQLFlowSelectStmt{
		Extended: true,
		ShowTrain: true,
		ShowTrainClause: $1}
}
;

end_of_stmt
: ';'         {}
;

train_clause
: TO TRAIN IDENT WITH attrs column_clause label_clause optional_using INTO IDENT {
	$$.Estimator = $3
	$$.TrainAttrs = $5
	$$.Columns = $6
	$$.Label = $7
	$$.TrainUsing = $8
	$$.Save = $10
  }
| TO TRAIN IDENT WITH attrs column_clause optional_using INTO IDENT {
	$$.Estimator = $3
	$$.TrainAttrs = $5
	$$.Columns = $6
	$$.TrainUsing = $7
	$$.Save = $9
}
| TO TRAIN IDENT WITH attrs label_clause optional_using INTO IDENT {
	$$.Estimator = $3
	$$.TrainAttrs = $5
	$$.Label = $6
	$$.TrainUsing = $7
	$$.Save = $9
}
| TO TRAIN IDENT label_clause optional_using INTO IDENT {
	$$.Estimator = $3
	$$.Label = $4
	$$.TrainUsing = $5
	$$.Save = $7
}
| TO TRAIN IDENT WITH attrs optional_using INTO IDENT {
	$$.Estimator = $3
	$$.TrainAttrs = $5
	$$.TrainUsing = $6
	$$.Save = $8
}
;

predict_clause
: TO PREDICT IDENT USING IDENT { $$.Into = $3; $$.Model = $5 }
| TO PREDICT IDENT WITH attrs USING IDENT { $$.Into = $3; $$.PredAttrs = $5; $$.Model = $7 }
;

explain_clause
: TO EXPLAIN IDENT optional_using { $$.TrainedModel = $3; $$.Explainer = $4 }
| TO EXPLAIN IDENT optional_using INTO IDENT { $$.TrainedModel = $3; $$.Explainer = $4; $$.ExplainInto = $6 }
| TO EXPLAIN IDENT WITH attrs optional_using { $$.TrainedModel = $3; $$.ExplainAttrs = $5; $$.Explainer = $6 }
| TO EXPLAIN IDENT WITH attrs optional_using INTO IDENT { $$.TrainedModel = $3; $$.ExplainAttrs = $5; $$.Explainer = $6; $$.ExplainInto = $8 }
;

evaluate_clause
: TO EVALUATE IDENT WITH attrs label_clause INTO IDENT { $$.ModelToEvaluate = $3; $$.EvaluateAttrs = $5; $$.EvaluateLabel = $6; $$.EvaluateInto = $8 }
| TO EVALUATE IDENT label_clause INTO IDENT { $$.ModelToEvaluate = $3; $$.EvaluateLabel = $4; $$.EvaluateInto = $6 }
;

run_clause
: TO RUN IDENT { $$.ImageName = $3; }
| TO RUN IDENT CMD stringlist { $$.ImageName = $3; $$.Parameters = $5 }
| TO RUN IDENT CMD stringlist INTO identlist { $$.ImageName = $3; $$.Parameters = $5; $$.OutputTables = $7 }
;

optimize_clause
: TO MAXIMIZE expr CONSTRAINT ConstraintExprList WITH attrs USING IDENT INTO IDENT {
	$$.Direction = "MAXIMIZE";
	$$.Objective = $3;
	$$.Constrants = $5;
	$$.OptimizeAttrs = $7;
	$$.Solver = $9;
	$$.OptimizeInto = $11;
}
| TO MAXIMIZE expr CONSTRAINT ConstraintExprList WITH attrs INTO IDENT {
	$$.Direction = "MAXIMIZE";
	$$.Objective = $3;
	$$.Constrants = $5;
	$$.OptimizeAttrs = $7;
	$$.OptimizeInto = $9;
}
| TO MINIMIZE expr CONSTRAINT ConstraintExprList WITH attrs USING IDENT INTO IDENT {
	$$.Direction = "MINIMIZE";
	$$.Objective = $3;
	$$.Constrants = $5;
	$$.OptimizeAttrs = $7;
	$$.Solver = $9;
	$$.OptimizeInto = $11;
}
| TO MINIMIZE expr CONSTRAINT ConstraintExprList WITH attrs INTO IDENT {
	$$.Direction = "MINIMIZE";
	$$.Objective = $3;
	$$.Constrants = $5;
	$$.OptimizeAttrs = $7;
	$$.OptimizeInto = $9;
};

show_train_clause
: SHOW TRAIN IDENT { $$.ModelName = $3; }
;

optional_using
: /* empty */  { $$ = "" }
| USING IDENT  { $$ = $2 }
;

column_clause
: COLUMN columns 				{ $$ = map[string]ExprList{"feature_columns" : $2} }
| COLUMN columns FOR IDENT 			{ $$ = map[string]ExprList{$4 : $2} }
| column_clause COLUMN columns FOR IDENT 	{ $$[$5] = $3 }
;

column
: '*'     { $$ = atomic(IDENT, "*") }
| IDENT   { $$ = atomic(IDENT, $1)  }
| funcall { $$ = $1 }
;

columns
: column             { $$ = ExprList{$1}     }
| columns ',' column { $$ = append($1, $3) }
;

label_clause
: LABEL IDENT  { $$ = $2 }
| LABEL STRING { $$ = $2[1:len($2)-1] }
;

attr
: IDENT '=' expr    { $$ = Attributes{$1 : $3} }
;

attrs
: attr              { $$ = $1 }
| attrs ',' attr    { $$ = attrsUnion($1, $3) }
;

funcall
: IDENT '(' ')'          { $$ = funcall($1, nil) }
| IDENT '(' ExprList ')' { $$ = funcall($1, $3)  }
;

ExprList
: expr              { $$ = ExprList{$1}     }
| ExprList ',' expr { $$ = append($1, $3) }
;

ConstraintExpr
: expr { $$ = &ConstraintExpr{expr: $1, groupby: ""} }
| expr GROUP BY IDENT { $$ = &ConstraintExpr{expr: $1, groupby: $4} }
;

ConstraintExprList
: ConstraintExpr { $$ = ConstraintExprList{$1} }
| ConstraintExprList ',' ConstraintExpr { $$ = append($1, $3) }
;

pythonlist
: '[' ']'           { $$ = nil }
| '[' ExprList ']'  { $$ = $2  }
;

stringlist
: STRING                 { $$ = []string{$1[1:len($1)-1]} }
| stringlist ',' STRING  { $$ = append($1, $3[1:len($3)-1]) }
;

identlist
: IDENT                  { $$ = []string{$1}}
| identlist ',' IDENT    { $$ = append($1, $3) }
;

expr
: NUMBER         { $$ = atomic(NUMBER, $1) }
| IDENT          { $$ = atomic(IDENT, $1)  }
| STRING         { $$ = atomic(STRING, $1) }
| pythonlist     { $$ = variadic('[', "square", $1) }
| '(' expr ')'   { $$ = unary('(', "paren", $2) } /* take '(' as the operator */
| '"' STRING '"'	{ $$ = unary('"', "quota", atomic(STRING,$2)) }
| '\'' STRING '\''	{ $$ = unary('\'', "quota", atomic(STRING,$2)) }
| funcall        { $$ = $1 }
| expr '+' expr  { $$ = binary('+', $1, $2, $3) }
| expr '-' expr  { $$ = binary('-', $1, $2, $3) }
| expr '*' expr  { $$ = binary('*', $1, $2, $3) }
| expr '/' expr  { $$ = binary('/', $1, $2, $3) }
| expr '%' expr  { $$ = binary('%', $1, $2, $3) }
| expr '=' expr  { $$ = binary('=', $1, $2, $3) }
| expr '<' expr  { $$ = binary('<', $1, $2, $3) }
| expr '>' expr  { $$ = binary('>', $1, $2, $3) }
| expr LE  expr  { $$ = binary(LE,  $1, $2, $3) }
| expr GE  expr  { $$ = binary(GE,  $1, $2, $3) }
| expr NE  expr  { $$ = binary(NE,  $1, $2, $3) }
| expr AND expr  { $$ = binary(AND, $1, $2, $3) }
| expr OR  expr  { $$ = binary(OR,  $1, $2, $3) }
| NOT expr %prec NOT    { $$ = unary(NOT, $1, $2) }
| '-' expr %prec UMINUS { $$ = unary('-', $1, $2) }
;

%%

/* Like Lisp's builtin function cdr. */
func (e *Expr) cdr() (r []string) {
	for i := 1; i < len(e.Sexp); i++ {
		r = append(r, e.Sexp[i].String())
	}
	return r
}

/* Convert ExprList to string slice. */
func (el ExprList) Strings() (r []string) {
	for i := 0; i < len(el); i++ {
		r = append(r, el[i].String())
	}
	return r
}

func (e *Expr) String() string {
	if e.Type == 0 { /* a compound expression */
		switch e.Sexp[0].Type {
		case '+', '*', '/', '%', '=', '<', '>', '!', LE, GE, AND, OR:
			if len(e.Sexp) != 3 {
				log.Panicf("Expecting binary expression, got %.10q", e.Sexp)
			}
			return fmt.Sprintf("%s %s %s", e.Sexp[1], e.Sexp[0].Value, e.Sexp[2])
		case '-':
			switch len(e.Sexp) {
			case 2:
				return fmt.Sprintf(" -%s", e.Sexp[1])
			case 3:
				return fmt.Sprintf("%s - %s", e.Sexp[1], e.Sexp[2])
			default:
				log.Panicf("Expecting either unary or binary -, got %.10q", e.Sexp)
			}
		case '(':
			if len(e.Sexp) != 2 {
				log.Panicf("Expecting ( ) as unary operator, got %.10q", e.Sexp)
			}
			return fmt.Sprintf("(%s)", e.Sexp[1])
		case '[':
			return "[" + strings.Join(e.cdr(), ", ") + "]"
		case NOT:
			return fmt.Sprintf("NOT %s", e.Sexp[1])
		case IDENT: /* function call */
			return e.Sexp[0].Value + "(" + strings.Join(e.cdr(), ", ") + ")"
		}
	} else {
		return fmt.Sprintf("%s", e.Value)
	}

	log.Panicf("Cannot print an unknown expression")
	return ""
}

func (s StandardSelect) String() string {
	return s.origin
}

var mu sync.Mutex // Protect the use of global variable parseResult.

func parseSQLFlowStmt(s string) (r *SQLFlowSelectStmt, idx int, e error) {
	defer func() {
		if r := recover(); r != nil {
			if err, ok := r.(error); ok {
				e = err
			} else {
				e = fmt.Errorf("%v", r)
			}
		}
	}()

	mu.Lock()
	defer mu.Unlock()

	parseResult = nil // Important! Clear out result from previous call.
	lex := newLexer(s)
	extendedSyntaxParse(lex) // extendedSyntaxParse is auto generated.
	idx = lex.pos
	if lex.err != nil {
		parseResult = nil
		idx = lex.previous
	}
	return parseResult, idx, lex.err
}
