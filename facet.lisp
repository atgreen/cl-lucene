;;;; facet.lisp --- Faceted counts.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; Count how a result set breaks down across :facet field values, using
;;;; Lucene's SortedSet doc-values faceting (no separate taxonomy index).
;;;; Documents are prepared at ADD-DOCUMENT time by the writer's FacetsConfig;
;;;; FACETS reads the counts back at search time.

(in-package #:cl-lucene)

(defun facets (searcher query dims &key (top 10))
  "Count the documents matching QUERY by their :facet values.  DIMS is a list
of facet dimension names (the field names used for :facet fields).  Returns an
alist mapping each dimension to a list of (label . count) conses, most frequent
first (an empty list for a dimension with no matching values).

Requires the index to contain at least one facet field; a QUERY of
(match-all-query) gives the overall counts."
  (start)
  (with-foreign-errors ("Lucene")
    (let* ((config (java-new "org.apache.lucene.facet.FacetsConfig" "()"))
           (state (java-new "org.apache.lucene.facet.sortedset.DefaultSortedSetDocValuesReaderState"
                            "(Lorg/apache/lucene/index/IndexReader;Lorg/apache/lucene/facet/FacetsConfig;)"
                            (searcher-reader searcher) config))
           (manager (java-new "org.apache.lucene.facet.FacetsCollectorManager" "()"))
           (collector (java-call (concatenate 'string "search(Lorg/apache/lucene/search/Query;"
                                              "Lorg/apache/lucene/search/CollectorManager;)Ljava/lang/Object;")
                                 (searcher-object searcher) (parse-query searcher query) manager))
           (counts (java-new "org.apache.lucene.facet.sortedset.SortedSetDocValuesFacetCounts"
                             (concatenate 'string "(Lorg/apache/lucene/facet/sortedset/"
                                          "SortedSetDocValuesReaderState;Lorg/apache/lucene/facet/FacetsCollector;)")
                             state collector)))
      (loop for dim in dims
            for result = (java-call (concatenate 'string "getTopChildren(ILjava/lang/String;"
                                                 "[Ljava/lang/String;)Lorg/apache/lucene/facet/FacetResult;")
                                    counts top (jstring (string dim))
                                    (make-java-array-of "java.lang.String" '()))
            collect (cons (string dim)
                          (when result
                            (loop for lv in (java-array-list (java-field-value result "labelValues"))
                                  collect (cons (lstring (java-field-value lv "label"))
                                                (java-field-value lv "count")))))))))
