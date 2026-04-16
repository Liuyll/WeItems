//
//  AddItemView.swift
//  WeItems
//

import SwiftUI
import PhotosUI

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ItemStore
    @ObservedObject var groupStore: GroupStore
    
    var defaultGroupId: UUID?
    
    @State private var name = ""
    @State private var details = ""
    @State private var price = ""
    @State private var selectedType: ItemType = .other
    @State private var selectedGroupId: UUID?
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var compressedImageData: Data?
    @State private var fullScreenImage: UIImage? = nil
    
    @State private var showingAddGroup = false
    @State private var showingDuplicateAlert = false
    @State private var spiritTravelCount = 0
    @State private var isLargeItem = false
    @State private var isPriceless = false
    @State private var ownedDate = Date()
    @State private var lifeGoodCount = 0
    @State private var savedItemName = ""
    @State private var celebrationKind: CelebrationKind?
    
    enum CelebrationKind: Identifiable {
        case spiritTravel
        case lifeGood
        var id: Int { hashValue }
    }
    
    private var isValid: Bool {
        if isPriceless {
            return !name.isEmpty
        }
        return !name.isEmpty && !price.isEmpty && Double(price) != nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 基本信息
                Section {
                    TextField("物品名称", text: $name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .submitLabel(.done)
                        .listRowSeparator(.hidden)
                    
                    if !isPriceless {
                        HStack {
                            Text("¥")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            TextField("价格", text: $price)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .keyboardType(.decimalPad)
                        }
                        .listRowSeparator(.hidden)
                    }
                    
                    Picker(selection: $selectedType) {
                        ForEach(ItemType.allCases, id: \.self) { type in
                            HStack(spacing: 6) {
                                type.iconImage(size: 16)
                                Text(type.rawValue)
                            }
                                .tag(type)
                        }
                    } label: {
                        Text("类型")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .listRowSeparator(.hidden)
                    
                    Toggle(isOn: $isLargeItem) {
                        Text("大件")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .listRowSeparator(.hidden)
                    
                    Toggle(isOn: $isPriceless) {
                        Text("无价之物")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .listRowSeparator(.hidden)
                    
                    DatePicker(selection: $ownedDate, displayedComponents: .date) {
                        Text("拥有日期")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .listRowSeparator(.hidden)
                } header: {
                    Text("基本信息")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                }
                
                // 分组选择
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // 无分组
                            Button {
                                selectedGroupId = nil
                            } label: {
                                Text("全部")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(selectedGroupId == nil ? .bold : .regular)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedGroupId == nil ? Color.blue.opacity(0.15) : Color(.systemGray5))
                                    )
                                    .foregroundStyle(selectedGroupId == nil ? .blue : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            ForEach(groupStore.groups) { group in
                                Button {
                                    selectedGroupId = group.id
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: group.icon)
                                            .font(.caption)
                                        Text(group.name)
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(selectedGroupId == group.id ? .bold : .regular)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedGroupId == group.id ? group.color.swiftUIColor.opacity(0.15) : Color(.systemGray5))
                                    )
                                    .foregroundStyle(selectedGroupId == group.id ? group.color.swiftUIColor : .primary)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            // 新增分组
                            Button {
                                showingAddGroup = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.caption)
                                    Text("新增")
                                        .font(.system(.subheadline, design: .rounded))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                                )
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 2)
                    .listRowSeparator(.hidden)
                } header: {
                    Text("所属分组")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                }
                
                // 图片选择
                Section {
                    if let imageData = selectedImageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .onTapGesture { fullScreenImage = uiImage }
                        
                        HStack(spacing: 0) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("更换")
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .frame(height: 20)
                            
                            Button {
                                selectedImageData = nil
                                compressedImageData = nil
                                selectedPhoto = nil
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("删除")
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowSeparator(.hidden)
                    } else {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            RoundedRectangle(cornerRadius: 0)
                                .fill(Color.blue)
                                .frame(height: 200)
                                .overlay(
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.white)
                                )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    }
                    
                    EmptyView()
                        .onChange(of: selectedPhoto) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    selectedImageData = data
                                    if let uiImage = UIImage(data: data) {
                                        compressedImageData = uiImage.jpegData(compressionQuality: 0.7)
                                    }
                                }
                            }
                        }
                        .frame(height: 0)
                } header: {
                    Text("照片")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                }
                
                // 详情
                Section {
                    TextEditor(text: $details)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(minHeight: 80)
                        .listRowSeparator(.hidden)
                } header: {
                    Text("详情描述")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                }
            }
            .navigationTitle("添加物品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveItem()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingAddGroup) {
                AddGroupView(groupStore: groupStore)
            }
            .fullScreenImageViewer(uiImage: $fullScreenImage)
            .fullScreenCover(item: $celebrationKind, onDismiss: {
                dismiss()
            }) { kind in
                switch kind {
                case .spiritTravel:
                    SpiritTravelCelebrationView(count: spiritTravelCount)
                case .lifeGood:
                    LifeGoodCelebrationView(count: lifeGoodCount, itemName: savedItemName, imageData: selectedImageData, details: details)
                }
            }
            .customInfoAlert(
                isPresented: $showingDuplicateAlert,
                title: "同名物品已存在",
                message: "已存在名为「\(name)」的物品，请更换名称后重试。"
            )
            .onAppear {
                selectedGroupId = defaultGroupId
            }
        }
    }
    
    private func saveItem() {
        let priceValue: Double
        if isPriceless {
            priceValue = 0
        } else {
            guard let parsed = Double(price) else { return }
            priceValue = parsed
        }
        
        // 检查是否存在同名物品
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.items.contains(where: { $0.name == trimmedName }) {
            showingDuplicateAlert = true
            return
        }
        
        let newItem = Item(
            name: name,
            details: details,
            purchaseLink: "",
            imageData: selectedImageData,
            compressedImageData: compressedImageData,
            imageChanged: selectedImageData != nil,
            price: priceValue,
            type: selectedType.rawValue,
            groupId: selectedGroupId,
            isLargeItem: isLargeItem,
            isPriceless: isPriceless,
            ownedDate: ownedDate
        )
        
        store.add(newItem)
        
        // 检查是否为精神旅行类型
        if selectedType == .outdoor {
            spiritTravelCount = countCurrentYearSpiritTravels()
            celebrationKind = .spiritTravel
        } else if selectedType == .lifeGood {
            lifeGoodCount = countLifeGoods()
            savedItemName = name
            celebrationKind = .lifeGood
        } else {
            dismiss()
        }
    }
    
    private func countCurrentYearSpiritTravels() -> Int {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        return store.items.filter { item in
            let itemYear = calendar.component(.year, from: item.createdAt)
            // 统计本年度所有精神旅行物品（包括已归档的，不包括已删除的）
            return item.type == ItemType.outdoor.rawValue && 
                   itemYear == currentYear &&
                   item.listType == .items
        }.count
    }
    
    private func countLifeGoods() -> Int {
        return store.items.filter { item in
            item.type == ItemType.lifeGood.rawValue && item.listType == .items
        }.count
    }
}

#Preview {
    AddItemView(store: ItemStore(), groupStore: GroupStore())
}
