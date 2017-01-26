require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class UploadedImageTest < ActiveSupport::TestCase
  test "should create image" do
    assert_difference 'UploadedImage.count' do
      create_uploaded_image
    end
  end

  test "should not upload a file that is not an image" do
    assert_no_difference 'UploadedImage.count' do
      assert_raises ActiveRecord::RecordInvalid do
        create_uploaded_image file: 'not-an-image.txt'
      end
    end
  end

  test "should not upload a big image" do
    assert_no_difference 'UploadedImage.count' do
      assert_raises ActiveRecord::RecordInvalid do
        create_uploaded_image file: 'ruby-big.png'
      end
    end
  end

  test "should not upload a small image" do
    assert_no_difference 'UploadedImage.count' do
      assert_raises ActiveRecord::RecordInvalid do
        create_uploaded_image file: 'ruby-small.png'
      end
    end
  end

  test "should not create image without file" do
    assert_no_difference 'UploadedImage.count' do
      assert_raises ActiveRecord::RecordInvalid do
        create_uploaded_image file: nil
      end
    end
  end

  test "should have public path" do
    t = create_uploaded_image
    assert_match /^http/, t.public_path
  end

  test "should not upload a heavy image" do
    assert_no_difference 'UploadedImage.count' do
      assert_raises ActiveRecord::RecordInvalid do
        create_uploaded_image file: 'rails-photo.jpg'
      end
    end
  end
  
  test "should create versions" do
    i = create_uploaded_image
    assert_not_nil i.file.thumbnail
    assert_not_nil i.file.embed
  end

  test "should not upload corrupted file" do
    assert_no_difference 'UploadedImage.count' do
      assert_raises ActiveRecord::RecordInvalid do
        create_uploaded_image file: 'corrupted-image.png'
      end
    end
  end

  test "should not upload if disk is full" do
    UploadedImage.any_instance.stubs(:save!).raises(Errno::ENOSPC)
    assert_no_difference 'UploadedImage.count' do
      assert_raises Errno::ENOSPC do
        create_uploaded_image
      end
    end
    UploadedImage.any_instance.unstub(:save!)
  end

  test "should not upload unsafe image (mocked)" do
    stub_config('clamav_service_path', 'http://localhost:8080/scan') do
      RestClient.stubs(:post).returns(OpenStruct.new(body: "Everything ok : false\n"))
      assert_no_difference 'UploadedImage.count' do
        assert_raises ActiveRecord::RecordInvalid do
          create_uploaded_image
        end
      end
      RestClient.unstub(:post)
    end
  end

  test "should upload safe image (mocked)" do
    stub_config('clamav_service_path', 'http://localhost:8080/scan') do
      RestClient.stubs(:post).returns(OpenStruct.new(body: "Everything ok : true\n"))
      assert_difference 'UploadedImage.count' do
        create_uploaded_image
      end
      RestClient.unstub(:post)
    end
  end
end