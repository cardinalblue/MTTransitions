//
//  CIImage+Extensions.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/6/3.
//

import CoreImage
import Foundation

public extension CIImage {

    func apply(alpha: CGFloat) -> CIImage {
        let filter = CIFilter(name: "CIColorMatrix")
        filter?.setDefaults()
        filter?.setValue(self, forKey: kCIInputImageKey)
        let alphaVector = CIVector.init(x: 0, y: 0, z: 0, w: alpha)
        filter?.setValue(alphaVector, forKey: "inputAVector")
        if let outputImage = filter?.outputImage {
            return outputImage
        }
        return self
    }
    
    func flipYCoordinate() -> CIImage {
        let flipYTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: extent.origin.y * 2 + extent.height)
        return transformed(by: flipYTransform)
    }

}
