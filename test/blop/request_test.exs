defmodule Blop.RequestTest do
  use ExUnit.Case
  alias Blop.Request

  describe "serialize/1" do
    test "noop" do
      req = Request.noop()
      assert Request.serialize(req) == "TAG NOOP\r\n"
    end

    test "capability" do
      req = Request.capability()
      assert Request.serialize(req) == "TAG CAPABILITY\r\n"
    end

    test "authenticate" do
      req = Request.authenticate("PLAIN")
      assert Request.serialize(req) == "TAG AUTHENTICATE PLAIN\r\n"
    end

    test "login" do
      req = Request.login("user", "pass")
      assert Request.serialize(req) == "TAG LOGIN user pass\r\n"
    end

    test "logout" do
      req = Request.logout()
      assert Request.serialize(req) == "TAG LOGOUT\r\n"
    end

    test "list" do
      req = Request.list()
      assert Request.serialize(req) == "TAG LIST \"\" *\r\n"

      req = Request.list("ref", "box")
      assert Request.serialize(req) == "TAG LIST ref box\r\n"
    end

    test "select" do
      req = Request.select("INBOX")
      assert Request.serialize(req) == "TAG SELECT INBOX\r\n"
    end

    test "append" do
      # Test raw params passing
      req = Request.append("INBOX (\\Seen) {10}")
      assert Request.serialize(req) == "TAG APPEND INBOX (\\Seen) {10}\r\n"
    end

    test "status" do
      req = Request.status("INBOX")
      assert Request.serialize(req) == "TAG STATUS INBOX\r\n"
    end

    test "fetch" do
      req = Request.fetch("1:5", "ALL")
      assert Request.serialize(req) == "TAG FETCH 1:5 ALL\r\n"
    end

    test "fetch with macro default" do
      req = Request.fetch("1")
      assert Request.serialize(req) == "TAG FETCH 1 BODY.PEEK[]\r\n"
    end
  end

  describe "sequence_set/1" do
    test "integer" do
      assert Request.sequence_set(1) == "1"
    end

    test "list" do
      assert Request.sequence_set([1, 2, 3]) == "1,2,3"
    end

    test "range step 1" do
      assert Request.sequence_set(1..5) == "1:5"
    end

    test "range step -1" do
      assert Request.sequence_set(5..1//-1) == "5:1"
    end
  end
end
