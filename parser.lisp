;;;; parser.lisp --- Query parsers.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; Richer alternatives to MAKE-SEARCHER's built-in classic parse: a
;;;; configurable classic parser, the forgiving SimpleQueryParser, and a
;;;; multi-field parser.  Each returns a parser object; PARSE turns a string
;;;; into a Query to hand to SEARCH / SEARCH-COUNT.

(in-package #:cl-lucene)

(defparameter *operators*
  '((:or . "OR") (:and . "AND"))
  "Keyword names for QueryParser.Operator (the default operator between terms).")

(defun query-parser (field &key (analyzer :standard) (default-operator :or)
                             allow-leading-wildcard (phrase-slop 0) fuzzy-min-sim)
  "A configured classic QueryParser over FIELD.  DEFAULT-OPERATOR is :or (any
term, the Lucene default) or :and (all terms).  ALLOW-LEADING-WILDCARD permits
patterns like *foo (slow).  PHRASE-SLOP sets the default slop for \"...\"
phrases.  FUZZY-MIN-SIM, if given, sets the default fuzzy similarity."
  (start)
  (let ((parser (java-new "org.apache.lucene.queryparser.classic.QueryParser"
                          "(Ljava/lang/String;Lorg/apache/lucene/analysis/Analyzer;)"
                          (jstring (string field)) (make-analyzer analyzer))))
    (java-call "setDefaultOperator(Lorg/apache/lucene/queryparser/classic/QueryParser$Operator;)V"
               parser (java-static-field "org.apache.lucene.queryparser.classic.QueryParser$Operator"
                                         (or (cdr (assoc default-operator *operators*))
                                             (error "Unknown operator ~S" default-operator))))
    (when allow-leading-wildcard
      (java-call "setAllowLeadingWildcard(Z)V" parser 1))
    (when (plusp phrase-slop)
      (java-call "setPhraseSlop(I)V" parser phrase-slop))
    (when fuzzy-min-sim
      (java-call "setFuzzyMinSim(F)V" parser (coerce fuzzy-min-sim 'single-float)))
    parser))

(defun field-weight-map (fields)
  "A java.util.Map<String,Float> from FIELDS, a list where each element is a
field name (weight 1.0) or a cons (name . weight)."
  (let ((map (java-new "java.util.HashMap" "()")))
    (dolist (field fields map)
      (destructuring-bind (name . weight) (if (consp field) field (cons field 1.0))
        (java-call "put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
                   map (jstring (string name)) (java-float weight))))))

(defun simple-query-parser (fields &key (analyzer :standard))
  "A SimpleQueryParser -- a forgiving parser that never throws on bad syntax.
FIELDS is a single field name, or a list of field names, or a list of
(name . weight) conses for weighted multi-field search."
  (start)
  (let ((analyzer (make-analyzer analyzer)))
    (if (and (stringp fields))
        (java-new "org.apache.lucene.queryparser.simple.SimpleQueryParser"
                  "(Lorg/apache/lucene/analysis/Analyzer;Ljava/lang/String;)"
                  analyzer (jstring fields))
        (java-new "org.apache.lucene.queryparser.simple.SimpleQueryParser"
                  "(Lorg/apache/lucene/analysis/Analyzer;Ljava/util/Map;)"
                  analyzer (field-weight-map (if (listp fields) fields (list fields)))))))

(defun multi-field-query-parser (fields &key (analyzer :standard))
  "A classic parser that searches several FIELDS at once (a list of names)."
  (start)
  (java-new "org.apache.lucene.queryparser.classic.MultiFieldQueryParser"
            "([Ljava/lang/String;Lorg/apache/lucene/analysis/Analyzer;)"
            (string-array fields) (make-analyzer analyzer)))

(defun parse (parser string)
  "Parse STRING into a Lucene Query using PARSER, from QUERY-PARSER,
SIMPLE-QUERY-PARSER, or MULTI-FIELD-QUERY-PARSER."
  (with-foreign-errors ("Lucene")
    (java-call "parse(Ljava/lang/String;)Lorg/apache/lucene/search/Query;"
               parser (jstring string))))
