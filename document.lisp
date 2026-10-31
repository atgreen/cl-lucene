;;;; document.lisp --- Analyzers, directories, and document fields.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-lucene)

;;; Analyzers

(defparameter *analyzers*
  '((:standard   . "org.apache.lucene.analysis.standard.StandardAnalyzer")
    (:keyword    . "org.apache.lucene.analysis.core.KeywordAnalyzer")
    (:whitespace . "org.apache.lucene.analysis.core.WhitespaceAnalyzer")
    (:simple     . "org.apache.lucene.analysis.core.SimpleAnalyzer")
    (:english    . "org.apache.lucene.analysis.en.EnglishAnalyzer"))
  "Keyword names for the analyzers cl-lucene can construct by name.")

(defun make-analyzer (spec)
  "An org.apache.lucene.analysis.Analyzer.  SPEC is one of the keywords in
*ANALYZERS* (:standard, :keyword, :whitespace, :simple, :english) or an
existing Analyzer object, which is returned unchanged."
  (if (keywordp spec)
      (let ((class (or (cdr (assoc spec *analyzers*))
                       (error "Unknown analyzer ~S; known: ~{~S~^ ~}"
                              spec (mapcar #'car *analyzers*)))))
        (start)
        (java-new class "()"))
      spec))

;;; Directories

(defstruct (index-directory (:constructor %make-index-directory)
                            (:conc-name dir-))
  "A handle to a Lucene storage directory and the path it lives at (or :MEMORY)."
  object
  path)

(defun open-directory (path)
  "Open, creating if needed, a Lucene index directory.  PATH is a pathname or
namestring for an on-disk index (opened with FSDirectory, memory-mapped where
the platform allows), or :MEMORY for a fresh in-memory directory.  Close the
result with CLOSE."
  (start)
  (if (eq path :memory)
      (%make-index-directory
       :object (java-new "org.apache.lucene.store.ByteBuffersDirectory" "()")
       :path :memory)
      (let ((dir (uiop:ensure-directory-pathname path)))
        (ensure-directories-exist dir)
        (%make-index-directory
         :object (java-static "org.apache.lucene.store.FSDirectory"
                              "open(Ljava/nio/file/Path;)Lorg/apache/lucene/store/FSDirectory;"
                              (java-path dir))
         :path dir))))

(defmethod close ((directory index-directory))
  (java-call "close()V" (dir-object directory))
  (values))

;;; Fields

(defparameter *vector-similarities*
  '((:euclidean . "EUCLIDEAN") (:cosine . "COSINE")
    (:dot-product . "DOT_PRODUCT") (:max-inner-product . "MAXIMUM_INNER_PRODUCT"))
  "Keyword names for the VectorSimilarityFunction a :vector field can use.")

(defun vector-similarity (name)
  "The VectorSimilarityFunction constant named by the keyword NAME."
  (java-static-field "org.apache.lucene.index.VectorSimilarityFunction"
                     (or (cdr (assoc name *vector-similarities*))
                         (error "Unknown vector similarity ~S" name))))

(defun make-field (name value &key (type :text) (store t) (similarity :euclidean))
  "Build a Lucene field named NAME holding VALUE.  TYPE is one of:
  :text    analyzed full-text, searchable word by word (TextField);
  :string  an exact, un-analyzed value, e.g. an id or tag, that is also
           sortable and facetable (KeywordField: indexed term + doc-values);
  :stored  stored but not indexed (StoredField);
  :int :long :float :double  a number, indexed for range and sort queries;
  :vector  a dense float vector for k-nearest-neighbour search
           (KnnFloatVectorField); VALUE is a sequence of reals and SIMILARITY
           is :euclidean (default), :cosine, :dot-product or :max-inner-product;
  :facet   a facet value (NAME is the dimension, VALUE its label), counted by
           FACETS; usually paired with a :string field to also filter on it;
  :geo     a geographic point (VALUE is (latitude longitude) in degrees),
           searched with GEO-DISTANCE-QUERY / GEO-BOX-QUERY;
  :sorted-string  a single-valued string with SortedDocValues (not searchable
           or stored) for GROUP-SEARCH to group on.
STORE (default T) keeps the original value so it can be read back from a hit;
it does not apply to :stored, :vector, :facet, :geo or :sorted-string."
  (let ((field-name (jstring (string name))))
    (ecase type
      (:text
       (java-new "org.apache.lucene.document.TextField"
                 "(Ljava/lang/String;Ljava/lang/String;Lorg/apache/lucene/document/Field$Store;)"
                 field-name (jstring (princ-to-string value)) (field-store store)))
      ((:string :keyword)
       (java-new "org.apache.lucene.document.KeywordField"
                 "(Ljava/lang/String;Ljava/lang/String;Lorg/apache/lucene/document/Field$Store;)"
                 field-name (jstring (princ-to-string value)) (field-store store)))
      (:vector
       (java-new "org.apache.lucene.document.KnnFloatVectorField"
                 "(Ljava/lang/String;[FLorg/apache/lucene/index/VectorSimilarityFunction;)"
                 field-name (float-array value) (vector-similarity similarity)))
      (:facet
       ;; A facet field: NAME is the dimension, VALUE its label.  The writer's
       ;; FacetsConfig turns it into the indexed doc-values at ADD-DOCUMENT time.
       (java-new "org.apache.lucene.facet.sortedset.SortedSetDocValuesFacetField"
                 "(Ljava/lang/String;[Ljava/lang/String;)"
                 field-name (string-array (list (princ-to-string value)))))
      (:geo
       ;; A geographic point; VALUE is (latitude longitude) in degrees.
       (destructuring-bind (latitude longitude) value
         (java-new "org.apache.lucene.document.LatLonPoint"
                   "(Ljava/lang/String;DD)"
                   field-name (coerce latitude 'double-float) (coerce longitude 'double-float))))
      (:sorted-string
       ;; A single-valued string with SortedDocValues (not searchable or
       ;; stored): what GROUP-SEARCH needs to group on.  Use a separate field
       ;; name from a searchable :string of the same value.
       (java-new "org.apache.lucene.document.SortedDocValuesField"
                 "(Ljava/lang/String;Lorg/apache/lucene/util/BytesRef;)"
                 field-name
                 (java-new "org.apache.lucene.util.BytesRef" "(Ljava/lang/CharSequence;)"
                           (jstring (princ-to-string value)))))
      (:stored
       (java-new "org.apache.lucene.document.StoredField"
                 "(Ljava/lang/String;Ljava/lang/String;)"
                 field-name (jstring (princ-to-string value))))
      (:int
       (java-new "org.apache.lucene.document.IntField"
                 "(Ljava/lang/String;ILorg/apache/lucene/document/Field$Store;)"
                 field-name (round value) (field-store store)))
      (:long
       (java-new "org.apache.lucene.document.LongField"
                 "(Ljava/lang/String;JLorg/apache/lucene/document/Field$Store;)"
                 field-name (round value) (field-store store)))
      (:float
       (java-new "org.apache.lucene.document.FloatField"
                 "(Ljava/lang/String;FLorg/apache/lucene/document/Field$Store;)"
                 field-name (coerce value 'single-float) (field-store store)))
      (:double
       (java-new "org.apache.lucene.document.DoubleField"
                 "(Ljava/lang/String;DLorg/apache/lucene/document/Field$Store;)"
                 field-name (coerce value 'double-float) (field-store store))))))

(defun field-spec->field (spec)
  "A Lucene field from SPEC: either a field object already, or a list
(NAME VALUE &key TYPE STORE) describing one for MAKE-FIELD."
  (if (consp spec)
      (destructuring-bind (name value &rest options) spec
        (apply #'make-field name value options))
      spec))
