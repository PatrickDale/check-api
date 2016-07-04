require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class SampleModel < ActiveRecord::Base
  has_annotations
end

class CommentTest < ActiveSupport::TestCase
  def setup
    super
    Comment.delete_index
    Comment.create_index
    sleep 1
  end

  test "should create comment" do
    assert_difference 'Comment.count' do
      create_comment(text: 'test')
    end
  end

  test "should set type automatically" do
    c = create_comment
    assert_equal 'comment', c.annotation_type
  end

  test "should have text" do
    assert_no_difference 'Comment.count' do
      create_comment(text: nil)
      create_comment(text: '')
    end
  end

  test "should have annotations" do
    s1 = SampleModel.create!
    assert_equal [], s1.annotations
    s2 = SampleModel.create!
    assert_equal [], s2.annotations
    
    c1a = create_comment
    assert_nil c1a.annotated
    c1b = create_comment
    assert_nil c1b.annotated
    c2a = create_comment
    assert_nil c2a.annotated
    c2b = create_comment
    assert_nil c2b.annotated
    
    s1.add_annotation c1a
    c1b.annotated = s1
    c1b.save

    s2.add_annotation c2a
    c2b.annotated = s2
    c2b.save
    
    sleep 1

    assert_equal s1, c1a.annotated
    assert_equal s1, c1b.annotated
    assert_equal [c1a.id, c1b.id].sort, s1.reload.annotations.map(&:id).sort

    assert_equal s2, c2a.annotated
    assert_equal s2, c2b.annotated
    assert_equal [c2a.id, c2b.id].sort, s2.reload.annotations.map(&:id).sort
  end

  test "should create version when comment is created" do
    c = nil
    assert_difference 'PaperTrail::Version.count' do
      c = create_comment(text: 'test')
    end
    assert_equal 1, c.versions.count
    v = PaperTrail::Version.last
    assert_equal 'create', v.event
    assert_equal({ 'annotation_type' => ['', 'comment'], 'text' => ['', 'test'] }, JSON.parse(v.object_changes))
  end

  test "should create version when comment is updated" do
    c = create_comment(text: 'foo')
    c.text = 'bar'
    c.save
    assert_equal 2, c.versions.count
    v = PaperTrail::Version.last
    assert_equal 'update', v.event
    assert_equal({ 'text' => ['foo', 'bar'] }, JSON.parse(v.object_changes))
  end

  test "should revert" do
    c = create_comment(text: 'Version 1')
    c.text = 'Version 2'; c.save
    c.text = 'Version 3'; c.save
    c.text = 'Version 4'; c.save
    assert_equal 4, c.versions.size

    c.revert
    assert_equal 'Version 3', c.text
    c = c.reload
    assert_equal 'Version 4', c.text

    c.revert_and_save
    assert_equal 'Version 3', c.text
    c = c.reload
    assert_equal 'Version 3', c.text

    c.revert
    assert_equal 'Version 2', c.text
    c.revert
    assert_equal 'Version 1', c.text
    c.revert
    assert_equal 'Version 1', c.text

    c.revert(-1)
    assert_equal 'Version 2', c.text
    c.revert(-1)
    assert_equal 'Version 3', c.text
    c.revert(-1)
    assert_equal 'Version 4', c.text
    c.revert(-1)
    assert_equal 'Version 4', c.text

    c = c.reload
    assert_equal 'Version 3', c.text
    c.revert_and_save(-1)
    c = c.reload
    assert_equal 'Version 4', c.text

    assert_equal 4, c.versions.size
  end

  test "should return whether it has an attribute" do
    c = create_comment
    assert c.has_attribute?(:text)
  end

  test "should have a single annotation type" do
    c = create_comment
    assert_equal 'annotation', c._type
  end

  test "should have context" do
    c = create_comment
    s = SampleModel.create
    assert_nil c.context
    c.context = s
    c.save
    assert_equal s, c.context
  end

  test "should get annotations from context" do
    context1 = SampleModel.create
    context2 = SampleModel.create
    annotated = SampleModel.create

    c1 = create_comment
    c1.context = context1
    c1.annotated = annotated
    c1.save

    c2 = create_comment
    c2.context = context2
    c2.annotated = annotated
    c2.save

    sleep 1

    assert_equal [c1.id, c2.id].sort, annotated.annotations.map(&:id).sort
    assert_equal [c1.id], annotated.annotations(context1).map(&:id)
    assert_equal [c2.id], annotated.annotations(context2).map(&:id)
  end

  test "should get columns as array" do
    assert_kind_of Array, Comment.columns
  end

  test "should get columns as hash" do
    assert_kind_of Hash, Comment.columns_hash
  end

  test "should not be abstract" do
    assert_not Comment.abstract_class?
  end
end