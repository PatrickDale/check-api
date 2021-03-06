require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class ProjectSourceTest < ActiveSupport::TestCase

  test "should create project source" do
    assert_difference 'ProjectSource.count' do
      create_project_source
    end
  end

  test "should get tags" do
    s = create_project_source
    t = create_tag annotated: s
    c = create_comment annotated: s
    assert_equal [t], s.tags
  end

  test "should get comments" do
    s = create_project_source
    t = create_tag annotated: s
    c = create_comment annotated: s
    assert_equal [c], s.comments
  end

   test "should get collaborators" do
    u1 = create_user
    u2 = create_user
    u3 = create_user
    s1 = create_project_source
    s2 = create_project_source
    c1 = create_comment annotator: u1, annotated: s1
    c2 = create_comment annotator: u1, annotated: s1
    c3 = create_comment annotator: u1, annotated: s1
    c4 = create_comment annotator: u2, annotated: s1
    c5 = create_comment annotator: u2, annotated: s1
    c6 = create_comment annotator: u3, annotated: s2
    c7 = create_comment annotator: u3, annotated: s2
    assert_equal [u1, u2].sort, s1.collaborators.sort
    assert_equal [u3].sort, s2.collaborators.sort
  end

  test "should have annotations" do
    s = create_project_source
    c1 = create_comment annotated: s
    c2 = create_comment annotated: s
    c3 = create_comment annotated: nil
    assert_equal [c1.id, c2.id].sort, s.reload.annotations.map(&:id).sort
  end

end
