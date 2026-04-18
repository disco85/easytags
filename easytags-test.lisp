(in-package :easytags-tests)

(5am:def-suite :suite1 :description "EasyTags Test Suite")
(5am:in-suite :suite1)

(5am:test test1
 (5am:is (equal '((1) (2))
                '((1) (2)))))
