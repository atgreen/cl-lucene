;;;; analysis.lisp --- Building analyzers.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; Beyond the named analyzers in MAKE-ANALYZER: compose a tokenizer and a
;;;; filter chain by SPI name (CUSTOM-ANALYZER), and route different fields to
;;;; different analyzers (PER-FIELD-ANALYZER).  The results are ordinary
;;;; analyzers, usable anywhere an :analyzer is accepted.

(in-package #:cl-lucene)

(defun custom-analyzer (&key (tokenizer "standard") char-filters token-filters)
  "Build an analyzer from named components, as Lucene's CustomAnalyzer does.
TOKENIZER is an SPI factory name (\"standard\", \"whitespace\", \"keyword\", ...),
optionally as a list (name args...) of alternating key/value strings.
CHAR-FILTERS and TOKEN-FILTERS are lists of such (name args...) specs, applied
in order.  For example:
  (custom-analyzer
    :tokenizer \"standard\"
    :token-filters '((\"lowercase\")
                     (\"stop\")
                     (\"snowballPorter\" \"language\" \"English\")))"
  (start)
  (flet ((name-of (spec) (string (if (consp spec) (car spec) spec)))
         (args-of (spec) (if (consp spec) (cdr spec) '())))
    (let ((builder (java-static "org.apache.lucene.analysis.custom.CustomAnalyzer"
                                "builder()Lorg/apache/lucene/analysis/custom/CustomAnalyzer$Builder;")))
      (java-call (concatenate 'string "withTokenizer(Ljava/lang/String;[Ljava/lang/String;)"
                              "Lorg/apache/lucene/analysis/custom/CustomAnalyzer$Builder;")
                 builder (jstring (name-of tokenizer)) (string-array (args-of tokenizer)))
      (dolist (filter char-filters)
        (java-call (concatenate 'string "addCharFilter(Ljava/lang/String;[Ljava/lang/String;)"
                                "Lorg/apache/lucene/analysis/custom/CustomAnalyzer$Builder;")
                   builder (jstring (name-of filter)) (string-array (args-of filter))))
      (dolist (filter token-filters)
        (java-call (concatenate 'string "addTokenFilter(Ljava/lang/String;[Ljava/lang/String;)"
                                "Lorg/apache/lucene/analysis/custom/CustomAnalyzer$Builder;")
                   builder (jstring (name-of filter)) (string-array (args-of filter))))
      (java-call "build()Lorg/apache/lucene/analysis/custom/CustomAnalyzer;" builder))))

(defun per-field-analyzer (default &rest field-analyzer-plist)
  "An analyzer that uses a different analyzer per field.  DEFAULT is the
fallback (an analyzer spec or object); FIELD-ANALYZER-PLIST alternates a field
name and an analyzer spec, e.g.
  (per-field-analyzer :standard \"id\" :keyword \"tags\" :whitespace)"
  (start)
  (let ((map (java-new "java.util.HashMap" "()")))
    (loop for (field spec) on field-analyzer-plist by #'cddr
          do (java-call "put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
                        map (jstring (string field)) (make-analyzer spec)))
    (java-new "org.apache.lucene.analysis.miscellaneous.PerFieldAnalyzerWrapper"
              "(Lorg/apache/lucene/analysis/Analyzer;Ljava/util/Map;)"
              (make-analyzer default) map)))
