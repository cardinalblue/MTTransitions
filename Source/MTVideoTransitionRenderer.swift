//
//  MTVideoTransitionRenderer.swift
//  MTTransitions
//
//  Created by xushuifeng on 2020/3/23.
//

import Foundation
import MetalPetal
import VideoToolbox

public class MTVideoTransitionRenderer: NSObject {
 
    let effect: MTTransition.Effect
    
    private let transition: MTTransition
    
    public init(effect: MTTransition.Effect) {
        self.effect = effect
        self.transition = effect.transition
        super.init()
    }
    
    public func renderPixelBuffer(_ destinationPixelBuffer: CVPixelBuffer,
                                  usingForegroundSourceBuffer foregroundPixelBuffer: CVPixelBuffer,
                                  andBackgroundSourceBuffer backgroundPixelBuffer: CVPixelBuffer,
                                  forTweenFactor tween: Float) {
        
        let foregroundImage = MTIImage(cvPixelBuffer: foregroundPixelBuffer, alphaType: .alphaIsOne)
        let backgroundImage = MTIImage(cvPixelBuffer: backgroundPixelBuffer, alphaType: .alphaIsOne)
        
        transition.inputImage = foregroundImage.oriented(.downMirrored)
        transition.destImage = backgroundImage.oriented(.downMirrored)
        transition.progress = tween

        if let output = transition.outputImage {
            try? MTTransition.context?.render(output, to: destinationPixelBuffer)
        }
    }
}

extension UIImage {
    convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        guard let image = cgImage else {
            return nil
        }
        self.init(cgImage: image)
    }

    convenience init(color: UIColor, size: CGSize) {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        let context = UIGraphicsGetCurrentContext()!

        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        self.init(cgImage: image.cgImage!)
    }
}
