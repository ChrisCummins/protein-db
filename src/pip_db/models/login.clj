(ns pip-db.models.login
  (:require [clojure.string :as str]
            [crypto.password.bcrypt :as crypto]
            [clojure.java.jdbc :as sql]))

(defn get-user [user]
  (sql/with-connection (System/getenv "DATABASE_URL")
    (sql/with-query-results results
      [(str "SELECT * FROM users WHERE email='" user "'")]
      (if (= results nil)
        nil (first (doall results))))))

(defn get-hash [plaintext]
  (crypto/encrypt plaintext))

(defn hashes-match? [plaintext hash]
  (crypto/check plaintext hash))

(defn credentials-are-valid? [user password]
  (hashes-match? password ((get-user user) :pass)))

(defn add-account [user password]
  (sql/with-connection (System/getenv "DATABASE_URL")
    (sql/insert-values :users
                       [:email :pass :user_type_id]
                       [user (get-hash password) 1]))
  (str "Add user accound - user: " user " pass: " (get-hash password)))

(defn attempt-register [user password]
  (if (not (get-user user))
    (add-account user password)
    (str "User account already exists " (str (get-user user)))))

(defn attempt-login [user password]
  (if (get-user user)
    (if (credentials-are-valid? user password)
      "Login successful!"
      "Incorrect password!")
    "User account does not exist"))