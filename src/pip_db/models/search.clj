(ns pip-db.models.search
  (:use [pip-db.query :only (AND OR EQ NE)])
  (:require [clojure.java.jdbc :as sql]
            [clojure.string :as str]))

(def max-no-of-returned-records 20)

(defn split-args [words]
  (when (and words (not (str/blank? words)))
    (str/split (str/trim words) #" +")))

(defn conditionals [params]
  (let [id      (str (get params "id"))
        q       (split-args (get params "q"))
        q_eq    (get params "q_eq")
        q_any   (split-args (get params "q_any"))
        q_ne    (split-args (get params "q_ne"))
        q_s     (get params "q_s")
        q_l     (get params "q_l")
        m       (get params "m")]

    (AND
     (EQ {:field "id" :value id :numeric true}) ; Match specific record ID
     (AND                               ; Match all keywords
      (for [word q]
        (OR
         (EQ {:field "name" :value word})
         (EQ {:field "alt_name" :value word}))))
     (OR                                ; Match exact phrase
      (EQ {:field "name" :value q_eq})
      (EQ {:field "alt_name" :value q_eq}))
     (OR                                ; Match any keywords
      (for [word q_any]
        (OR
         (EQ {:field "name" :value word})
         (EQ {:field "alt_name" :value word}))))
     (AND                               ; Exclude keywords
      (for [word q_ne]
        (AND
         (NE {:field "name" :value word})
         (NE {:field "alt_name" :value word}))))
     (EQ {:field "source" :value q_s})
     (EQ {:field "organ" :value q_l})
     (EQ {:field "method" :value m}))))

;; ### Query components
;;
;; First off, we must define the table within which we are performing
;; look-ups.
(def query-table "records")

;; We can now take a query map and use this to generate a SQL
;; query. If the query map is empty, then we return an empty string.
(defn query [params]
  (let [conditions (conditionals params)]
    (if (str/blank? conditions)
      ""
      (str "SELECT * FROM " query-table " WHERE " conditions))))

;; This SQL query counts the number of records in the database.
(def no-of-records-query
  (str "SELECT count(*) AS exact_count FROM " query-table))

;; Construct a search results map from a set of search parameters and
;; a list of matching records.
(defn search-response [params matching-records no-of-records]
  (let [returned-records (take max-no-of-returned-records matching-records)]
    {:query                      params
     :no_of_records              no-of-records
     :no_of_matches              (count matching-records)
     :no_of_returned_records     (count returned-records)
     :max_no_of_returned_records max-no-of-returned-records
     :records                    returned-records}))

;; Fetch a vector of records for a given query map. We wrap the entire
;; query in a try/catch block in order to catch an SQL exception when
;; the query returns no results: "org.postgresql.util.PSQLException:
;; No results were returned by the query."
(defn search-results [params]
  (sql/with-connection (System/getenv "DATABASE_URL")
    (try (sql/with-query-results results [(query params)]
           (apply vector (doall results)))
         (catch Exception e []))))

;; Fetch the number of records within the database.
(defn no-of-records []
  (sql/with-connection (System/getenv "DATABASE_URL")
    (sql/with-query-results result [no-of-records-query]
      (((apply vector (doall result)) 0) :exact_count))))

(defn search [params]
  (search-response params (search-results params) (no-of-records)))
