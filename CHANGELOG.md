# Changelog

All notable changes to cl-lucene are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-31

First release. cl-lucene is a native Common Lisp API for [Apache
Lucene](https://lucene.apache.org/), running the real Lucene library on
[OpenLDK](https://github.com/atgreen/openldk) — which transpiles Lucene's Java
bytecode to Common Lisp that SBCL compiles to native machine code — so there is
no JVM and no foreign-function bridge between the Lisp and the index.

This release covers the Lucene features a search application reaches for first,
each with a Lispy interface and a test behind it:

### Added

- Directories: on-disk (`FSDirectory`/`MMapDirectory`, memory-mapped) and
  in-memory (`ByteBuffersDirectory`).
- Indexing: writers with create/append semantics, document add/update/delete,
  commit, and nested parent/child document blocks.
- Field types: full-text, string/keyword, stored, numeric (int/long/float/
  double), vector (k-NN float embeddings), facet, geo-point, and sortable
  string.
- Query builders: term, phrase, prefix, wildcard, fuzzy, regexp, range,
  boolean, boost, k-NN vector, proximity (interval), geo distance, geo box,
  match-all, and block-join.
- Query parsers: the classic query parser, the simple query parser, and the
  multi-field query parser.
- Analysis: standard, keyword, whitespace, simple, and English analyzers,
  custom analyzer construction, and per-field analyzers.
- Searching: ranked search over a query string or a built query, result counts,
  sorting, `searchAfter` pagination, score explanations, hit highlighting,
  faceted counts, and result grouping.
- Autocomplete: an infix suggester with weighted entries.

### Notes

- Requires a local OpenLDK checkout; see the README for setup. Verified against
  Apache Lucene 10.6.0 on SBCL 2.6.9 and JDK 25.
