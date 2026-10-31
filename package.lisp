;;;; package.lisp --- Package definition for cl-lucene.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(defpackage #:cl-lucene
  (:use #:cl)
  (:nicknames #:lucene)
  (:shadow #:search #:close)
  (:import-from #:openldk.interop
                #:start-runtime #:maven-jar
                #:java-new #:java-call #:java-static #:java-static-field
                #:jstring #:lstring #:make-java-array-of #:java-array-list
                #:java-fields #:java-instance-p #:with-foreign-errors)
  (:export
   ;; runtime
   #:start #:*lucene-version* #:*lucene-artifacts*
   ;; analyzers & directories
   #:make-analyzer #:custom-analyzer #:per-field-analyzer
   #:open-directory #:index-directory #:index-directory-p
   ;; closing (generic over writers, searchers, directories)
   #:close
   ;; writing
   #:make-writer #:with-writer #:writer #:writer-p
   #:make-field #:add-document #:build-document
   #:commit #:delete-all #:delete-documents #:update-document
   ;; query builders
   #:term #:match-all-query #:term-query #:phrase-query #:prefix-query
   #:wildcard-query #:fuzzy-query #:regexp-query #:range-query #:boolean-query
   #:boost-query #:knn-query #:near-query #:geo-distance-query #:geo-box-query
   ;; query parsers
   #:query-parser #:simple-query-parser #:multi-field-query-parser #:parse
   ;; searching
   #:make-searcher #:with-searcher #:searcher #:searcher-p
   #:search #:search-count #:explain #:facets
   ;; grouping
   #:group-search #:group #:group-p #:group-value #:group-hits #:group-total
   ;; nested documents / block join
   #:add-block #:block-join-query
   ;; autocomplete
   #:make-suggester #:suggest-add #:suggest-commit #:suggest #:suggester #:suggester-p
   ;; results
   #:hit #:hit-p #:hit-id #:hit-score #:hit-fields #:hit-field #:hit-snippet))
