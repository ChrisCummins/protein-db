(ns pip-db.test.query
  (:use clojure.test)
  (:require [pip-db.query :as dut]))

(def test-eq {:query  (dut/EQ {:field "foo" :value "bar"})
              :string "(LOWER(foo) LIKE LOWER('%bar%'))"})

(def test-ne {:query  (dut/NE {:field "foo" :value "bar"})
              :string "(LOWER(foo) NOT LIKE LOWER('%bar%'))"})

(deftest EQ
  (testing "Standard query"
    (is (= (test-eq :query)
           (test-eq :string))))

  (testing "Empty query value"
    (is (= (dut/EQ {:field "foo" :value ""})
           "")))

  (testing "Missing value key"
    (is (= (dut/EQ {:field "foo"})
           ""))))

(deftest NE
  (testing "Standard query"
    (is (= (test-ne :query)
           (test-ne :string))))

  (testing "Empty query value"
    (is (= (dut/NE {:field "foo" :value ""})
           "")))

  (testing "Missing value key"
    (is (= (dut/NE {:field "foo"})
           ""))))

(deftest compound-condition
  (testing "Single condition"
    (is (= (dut/compound-condition " + " '("a"))
           "(a)")))

  (testing "Multiple conditions"
    (is (= (dut/compound-condition " + " '("a" "b" "c" "d"))
           "(a + b + c + d)")))

  (testing "No conditions"
    (is (= (dut/compound-condition " + " '("" "  " "()" " ()" " ( )  "))
           "")))

  (testing "Strip empty conditions"
    (is (= (dut/compound-condition " + " '("a" "  " "b"))
           "(a + b)")))

  (testing "Sequences of conditions"
    (is (= (dut/compound-condition " + " (for [x '("a" "b")] x))
           "(a + b)"))))

(deftest AND
  (testing "Single condition"
    (is (= (dut/AND "a")
           "(a)")))

  (testing "Multiple conditions"
    (is (= (dut/AND "a" "b" "c" "d")
           "(a AND b AND c AND d)")))

  (testing "Sequences of conditions"
    (is (= (dut/AND (for [x '("a" "b")] x))
           "(a AND b)")))

  (testing "Mixed sequences and strings"
    (is (= (dut/AND "A" (for [x '("a" "b")] x) "B")
           "(A AND a AND b AND B)")))

  (testing "Single AND condition"
    (is (= (dut/AND (test-eq :query))
           (str "(" (test-eq :string) ")"))))

  (testing "Multiple AND conditions"
    (is (= (dut/AND (test-eq :query) (test-eq :query))
           (str "(" (test-eq :string) " AND " (test-eq :string) ")")))))

(deftest OR
  (testing "Single condition"
    (is (= (dut/OR "a")
           "(a)")))

  (testing "Multiple conditions"
    (is (= (dut/OR "a" "b" "c" "d")
           "(a OR b OR c OR d)")))

  (testing "Sequences of conditions"
    (is (= (dut/OR (for [x '("a" "b")] x))
           "(a OR b)")))

  (testing "Mixed sequences and strings"
    (is (= (dut/OR "A" (for [x '("a" "b")] x) "B")
           "(A OR a OR b OR B)")))

  (testing "Single AND condition"
    (is (= (dut/OR (test-eq :query))
           (str "(" (test-eq :string) ")"))))

  (testing "Multiple AND conditions"
    (is (= (dut/OR (test-eq :query) (test-eq :query))
           (str "(" (test-eq :string) " OR " (test-eq :string) ")")))))
