what does this function `let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -frfaceSize.height)` do in the following snippet?
--------------------------------------------------------------------------------------------------------------------------------------------------------

func getRotatedCroppedImage(from pixelBuffer: CVPixelBuffer, with observation: VNFaceObservation) -> UIImage? {
        // Convert pixel buffer to UIImage
        guard let faceImage = UIImage(pixelBuffer: pixelBuffer) else { // width = 3088, height = 2316
            print("Failed to convert pixel buffer to UIImage.")
            return nil
        }
        
        let frfaceSize = faceImage.size // width=3088, height=2316

        // Get the bounding box of the face in image coordinates
        let boundingBox = observation.boundingBox // 0-1
       
        // coordinates of camera and world
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -frfaceSize.height)
        let translate = CGAffineTransform.identity.scaledBy(x: frfaceSize.width, y: frfaceSize.height)
        let facebounds = boundingBox.applying(translate).applying(transform)
        
        // Crop the face image
        let croppedImage = faceImage.crop(to: facebounds)
       
        // Resize the image to 224x224
        let resizedRotatedCroppedImage = croppedImage?.resize(to: CGSize(width: 224, height: 224))
        
        return resizedRotatedCroppedImage
    }