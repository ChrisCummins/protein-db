(ns pip-db.test.views.record
  (:use clojure.test)
  (:require [pip-db.views.record :as dut]))

(deftest properties
  (testing "Testing tree structure"
    (is (= (dut/properties "foo")
           [:table#properties.table.table-striped.table-bordered
            [:tbody '("foo")]]))))

(deftest property
  (testing "Property with no value"
    (is (= (dut/property "foo" {} :nonexistent-value)
           nil)))

  (testing "Property with value"
    (is (= (dut/property "foo" {:bar "foo"} :bar)
           [:tr.property {:data-key "bar"}
            [:td.description "foo"] [:td.value "foo"]]))))

(deftest extern-links
  (testing "No external links"
    (is (= (dut/extern-links)
           [:div.panel.panel-primary.panel-extern
            [:div.panel-heading [:h3.panel-title "External Links"]]
            [:div.panel-body [:ul.panel-extern-list nil]]])))

  (testing "External links"
    (is (= (dut/extern-links "foo")
           [:div.panel.panel-primary.panel-extern
            [:div.panel-heading [:h3.panel-title "External Links"]]
            [:div.panel-body [:ul.panel-extern-list '("foo")]]]))))

(deftest extern
  (testing "No URL"
    (is (= (dut/extern "foo" "")
           nil)))

  (testing "With URL"
    (is (= (dut/extern "foo" "bar")
           [:li [:a.btn.btn-success.btn-block
                 {:href "bar", :target "_blank"} "foo"]]))))

(deftest record
  (testing "Page title and heading"
    (is (= (class (dut/record {:name "foo"}))
           java.lang.String))))